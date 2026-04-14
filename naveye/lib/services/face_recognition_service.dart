import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:path_provider/path_provider.dart';
import '../models/person_model.dart';
import 'database_service.dart';

class FaceMatch {
  final String name;
  final String imagePath;
  final double confidence;
  const FaceMatch({required this.name, required this.imagePath, required this.confidence});
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceRecognitionService — MobileFaceNet (ArcFace, WebFace600K) via ONNX
//
// Model:  mobilefacenet.onnx  (~13 MB, MIT licence)
// Input:  float32 NCHW [1, 3, 112, 112], values normalised to [-1, 1]
//         via (pixel / 255.0 − 0.5) / 0.5
// Output: float32 [1, 512] — 512-dim L2-normalised face embedding
//
// Pipeline per frame:
//   ML Kit detects face on FULL frame → crop + eye-align → 112×112 → normalise
//   → ONNX inference → 512-dim embedding → cosine similarity vs. DB
//
// Storage schema:
//   Each person stores N × 512 values concatenated in the embedding column.
//   N = number of registration photos with a detected face (up to 3).
//   Matching uses avg-of-top-2 per-angle cosine similarity:
//   score each 512-dim chunk against the live embedding, take the average of
//   the two highest scores. Requires two angles to agree — reduces false matches.
// ─────────────────────────────────────────────────────────────────────────────
class FaceRecognitionService {
  static final FaceRecognitionService instance = FaceRecognitionService._();
  FaceRecognitionService._();

  late FaceDetector _detector;
  OrtSession?       _session;
  List<Person>      _knownPeople  = [];
  bool              _initialized  = false;

  String? _pendingMatchName;
  int     _pendingCount = 0;
  String? _tempFilePath;

  // 3 consecutive frames required — raises the bar so a single accidental
  // high-score frame (lighting flare, partial occlusion) cannot trigger a
  // false announcement. Genuine matches are stable across frames at 30 fps.
  static const int _confirmFrames = 3;
  // Embedding dimension produced by MobileFaceNet
  static const int _embDim = 512;

  // ── Initialise ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) {
      await refreshKnownPeople();
      return;
    }
    // ML Kit face detector (landmarks needed for eye-alignment)
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks:      true,
        enableContours:       false,
        enableClassification: false,
        performanceMode:      FaceDetectorMode.accurate,
        minFaceSize:          0.07,
      ),
    );

    // Load MobileFaceNet ONNX model
    try {
      OrtEnv.instance.init();
      final modelData = await rootBundle.load('assets/models/mobilefacenet.onnx');
      final bytes = modelData.buffer.asUint8List(
          modelData.offsetInBytes, modelData.lengthInBytes);
      final opts = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(2);
      _session = OrtSession.fromBuffer(bytes, opts);
      debugPrint('FaceNet: MobileFaceNet ONNX loaded — '
          'inputs=${_session!.inputNames}, outputs=${_session!.outputNames}');
    } catch (e) {
      debugPrint('FaceNet: ONNX load failed — $e');
    }

    _initialized = true;
    await refreshKnownPeople();
  }

  Future<void> refreshKnownPeople() async {
    final all = await DatabaseService.instance.getAllPersons();
    _knownPeople = all.where((p) => p.embedding.isNotEmpty).toList();
    debugPrint('FaceNet DB: ${_knownPeople.length} people with embeddings');
  }

  // ── Extract embedding from a saved photo (called once on registration) ──────
  Future<List<double>?> extractEmbeddingFromFile(String imagePath) async {
    if (!_initialized) await init();
    if (_session == null) {
      debugPrint('FaceNet: ONNX session not ready');
      return null;
    }
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        debugPrint('FaceEmbed: no face in $imagePath');
        return null;
      }
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(Uint8List.fromList(bytes));
      if (image == null) return null;

      final emb = _computeEmbedding(image, faces.first);
      if (emb == null) return null;
      debugPrint('FaceEmbed: extracted $_embDim-dim MobileFaceNet embedding');
      return emb;
    } catch (e) {
      debugPrint('FaceEmbed error: $e');
      return null;
    }
  }

  // ── Recognise faces in a live camera frame ──────────────────────────────────
  //
  // IMPORTANT: pass the FULL camera frame, not a pre-cropped region.
  // ML Kit runs on the full-resolution frame so it can detect faces at natural
  // scale (better landmarks, better alignment).  The [pxMin/pyMin/pxMax/pyMax]
  // arguments are the YOLO-detected person bounding box in NORMALISED [0,1]
  // coordinates.  Any face whose centre falls inside this box is preferred.
  // This selects the correct person when multiple people are in the frame.
  Future<FaceMatch?> recogniseInFrame(
    img.Image fullFrame, {
    double pxMin = 0.0, double pyMin = 0.0,
    double pxMax = 1.0, double pyMax = 1.0,
  }) async {
    if (!_initialized || _knownPeople.isEmpty || _session == null) return null;
    try {
      _tempFilePath ??=
          '${(await getTemporaryDirectory()).path}/nav_face_live.jpg';
      final tempFile = File(_tempFilePath!);
      await tempFile.writeAsBytes(img.encodeJpg(fullFrame, quality: 85));

      final inputImage = InputImage.fromFilePath(tempFile.path);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        debugPrint('FaceMatch: no face in frame');
        return null;
      }

      // ── Select the face that belongs to the YOLO-detected person ─────────
      // Filter faces whose bounding-box CENTRE falls inside the normalised
      // person bbox.  This avoids misidentifying a bystander's face.
      final fw = fullFrame.width.toDouble();
      final fh = fullFrame.height.toDouble();
      final candidates = faces.where((f) {
        final cx = (f.boundingBox.left + f.boundingBox.width  / 2) / fw;
        final cy = (f.boundingBox.top  + f.boundingBox.height / 2) / fh;
        return cx >= pxMin && cx <= pxMax && cy >= pyMin && cy <= pyMax;
      }).toList();

      final Face face;
      if (candidates.isEmpty) {
        // No face centre inside the YOLO person box — YOLO and ML Kit bboxes
        // are slightly different coordinate systems; fall back to nearest face.
        debugPrint('FaceMatch: no face inside person bbox — using largest face');
        face = faces.reduce((a, b) =>
            (a.boundingBox.width * a.boundingBox.height) >
            (b.boundingBox.width * b.boundingBox.height)
                ? a : b);
      } else {
        // Pick the largest candidate (highest resolution → best embedding)
        face = candidates.reduce((a, b) =>
            (a.boundingBox.width * a.boundingBox.height) >
            (b.boundingBox.width * b.boundingBox.height)
                ? a : b);
      }

      // ── Face-size guard ────────────────────────────────────────────────────
      // With the full frame the face occupies a smaller fraction than when using
      // a head crop, so the threshold is lowered to 1.5 %.
      // ML Kit's minFaceSize=0.07 already rejects very tiny faces, so anything
      // ML Kit returns here will comfortably pass this guard at up to ~4 m.
      final facePx = face.boundingBox.width * face.boundingBox.height;
      final imgPx  = fullFrame.width * fullFrame.height;
      final frac   = imgPx > 0 ? facePx / imgPx : 0.0;
      if (frac < 0.015) {
        debugPrint('FaceMatch: face too small '
            '(${(frac * 100).toStringAsFixed(1)}%) — too far away');
        return null;
      }

      final embedding = _computeEmbedding(fullFrame, face);
      if (embedding == null) return null;

      final rawMatch = _findBestMatch(embedding);

      FaceMatch? confirmed;
      if (rawMatch != null) {
        if (rawMatch.name == _pendingMatchName) {
          _pendingCount++;
        } else {
          _pendingMatchName = rawMatch.name;
          _pendingCount     = 1;
        }
        if (_pendingCount >= _confirmFrames) {
          confirmed = rawMatch;
          debugPrint('FaceMatch CONFIRMED: ${rawMatch.name} '
              '(${(rawMatch.confidence * 100).toStringAsFixed(1)}%)');
        } else {
          debugPrint('FaceMatch pending: ${rawMatch.name} '
              '($_pendingCount/$_confirmFrames)');
        }
      } else {
        _pendingMatchName = null;
        _pendingCount     = 0;
      }
      return confirmed;
    } catch (e) {
      debugPrint('FaceRecognise error: $e');
      return null;
    }
  }

  // ── Avg-of-top-2 scoring ────────────────────────────────────────────────────
  // Stored embedding = N × _embDim values concatenated.
  // Score each chunk vs. query, take avg of the best 2 — requires two
  // angles to agree, which eliminates most false positives.
  double _bestScoreAgainstPerson(List<double> query, List<double> stored) {
    if (stored.length < _embDim) return 0.0;
    if (stored.length == _embDim) return _cosineSimilarity(query, stored);

    final count  = stored.length ~/ _embDim;
    final scores = <double>[];
    for (int i = 0; i < count; i++) {
      final chunk = stored.sublist(i * _embDim, (i + 1) * _embDim);
      scores.add(_cosineSimilarity(query, chunk));
    }
    scores.sort((a, b) => b.compareTo(a));
    final take = scores.length >= 2 ? 2 : scores.length;
    return scores.take(take).reduce((a, b) => a + b) / take;
  }

  FaceMatch? _findBestMatch(List<double> embedding) {
    double bestScore   = 0.0;
    double secondScore = 0.0;
    Person? bestPerson;

    for (final person in _knownPeople) {
      if (person.embedding.length < _embDim) continue;
      final score = _bestScoreAgainstPerson(embedding, person.embedding);
      debugPrint('  vs ${person.name}: ${(score * 100).toStringAsFixed(1)}%');
      if (score > bestScore) {
        secondScore = bestScore;
        bestScore   = score;
        bestPerson  = person;
      } else if (score > secondScore) {
        secondScore = score;
      }
    }

    // ── Threshold ─────────────────────────────────────────────────────────────
    // MobileFaceNet (ArcFace) cosine similarity (L2-normalised embeddings):
    //   Same person, good lighting  : 0.50 – 0.90
    //   Different people            : 0.05 – 0.42
    // FIX-A: raised from 0.35 → 0.52. At 0.35 strangers routinely scored
    // 0.36–0.44 and triggered false "That is [name]" announcements.
    // At 0.52 the gap between genuine (≥0.55) and impostor (≤0.44) is clear.
    const double kThreshold = 0.52;

    // ── Margin check ──────────────────────────────────────────────────────────
    // FIX-B: Single-person DB virtual runner-up raised 0.15 → 0.30.
    // Previously: bestScore=0.36, virtual=0.15, margin=0.21 ≥ 0.10 → PASSED (wrong)
    // Now:        bestScore=0.36, virtual=0.30, margin=0.06 < 0.10 → REJECTED (correct)
    // A genuine match scores ≥0.52 with margin ≥0.22 — well above both gates.
    final effectiveSecond = _knownPeople.length == 1 ? 0.30 : secondScore;
    final margin   = bestScore - effectiveSecond;
    final okMargin = margin >= 0.10;

    if (bestScore >= kThreshold && okMargin && bestPerson != null) {
      return FaceMatch(
          name:       bestPerson.name,
          imagePath:  bestPerson.imagePath,
          confidence: bestScore);
    }
    debugPrint('FaceMatch: rejected — '
        'score=${bestScore.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)}');
    return null;
  }

  // ── Compute 512-dim MobileFaceNet embedding ─────────────────────────────────
  //
  // Pipeline:
  //   1. Crop face bounding box with 30% padding
  //   2. Eye-landmark alignment (rotate so eyes are horizontal)
  //   3. Resize to 112×112 RGB
  //   4. Normalise: (pixel / 255.0 − 0.5) / 0.5  →  [-1, 1]
  //   5. NCHW Float32List  [1, 3, 112, 112]
  //   6. ONNX inference → [1, 512]
  //   7. L2 normalise output
  List<double>? _computeEmbedding(img.Image image, Face face) {
    try {
      final box = face.boundingBox;

      // 1. Crop with generous padding
      final padW = box.width  * 0.30;
      final padH = box.height * 0.30;
      final x = (box.left   - padW).toInt().clamp(0, image.width  - 1);
      final y = (box.top    - padH).toInt().clamp(0, image.height - 1);
      final w = (box.width  + 2 * padW).toInt().clamp(1, image.width  - x);
      final h = (box.height + 2 * padH).toInt().clamp(1, image.height - y);
      var crop = img.copyCrop(image, x: x, y: y, width: w, height: h);

      // 2. Eye-alignment
      final le = face.landmarks[FaceLandmarkType.leftEye];
      final re = face.landmarks[FaceLandmarkType.rightEye];
      if (le != null && re != null) {
        final leX = le.position.x.toDouble() - x;
        final leY = le.position.y.toDouble() - y;
        final reX = re.position.x.toDouble() - x;
        final reY = re.position.y.toDouble() - y;
        final angle = atan2(reY - leY, reX - leX) * 180 / pi;
        if (angle.abs() > 1 && angle.abs() < 45) {
          crop = img.copyRotate(crop, angle: angle);
        }
      }

      // 3. Resize to 112×112 RGB (keep colour — neural net uses colour)
      final resized = img.copyResize(crop, width: 112, height: 112,
          interpolation: img.Interpolation.linear);

      // 4 + 5. Normalise + NCHW layout
      final input = _toNCHW(resized);

      // 6. ONNX inference
      final emb = _runOnnx(input);
      if (emb.isEmpty) return null;

      // 7. L2 normalise
      return _l2Normalize(emb);
    } catch (e) {
      debugPrint('FaceEmbed compute error: $e');
      return null;
    }
  }

  // ── Build NCHW Float32List for model input ──────────────────────────────────
  Float32List _toNCHW(img.Image image) {
    const S   = 112;
    final data = Float32List(3 * S * S);
    final rOff = 0 * S * S;
    final gOff = 1 * S * S;
    final bOff = 2 * S * S;
    for (int iy = 0; iy < S; iy++) {
      for (int ix = 0; ix < S; ix++) {
        final p   = image.getPixel(ix, iy);
        final idx = iy * S + ix;
        // (pixel/255 - 0.5) / 0.5  maps [0,255] → [-1, 1]
        data[rOff + idx] = (p.r.toDouble() / 255.0 - 0.5) / 0.5;
        data[gOff + idx] = (p.g.toDouble() / 255.0 - 0.5) / 0.5;
        data[bOff + idx] = (p.b.toDouble() / 255.0 - 0.5) / 0.5;
      }
    }
    return data;
  }

  // ── Run ONNX session → 512-dim embedding ────────────────────────────────────
  List<double> _runOnnx(Float32List input) {
    if (_session == null) return [];
    try {
      final tensor = OrtValueTensor.createTensorWithDataList(
          input, [1, 3, 112, 112]);
      final runOpts = OrtRunOptions();
      final outputs = _session!.run(runOpts, {_session!.inputNames.first: tensor});
      tensor.release();
      runOpts.release();

      if (outputs.isEmpty || outputs[0] == null) return [];
      final outTensor = outputs[0]!;
      final raw       = outTensor.value as List;
      outTensor.release();

      // Output shape [1, 512] → raw[0] is the 512-element list
      final batch = raw[0] as List;
      return batch.map((v) => (v as num).toDouble()).toList();
    } catch (e) {
      debugPrint('FaceNet ONNX run error: $e');
      return [];
    }
  }

  List<double> _l2Normalize(List<double> v) {
    final norm = sqrt(v.map((x) => x * x).reduce((a, b) => a + b));
    if (norm < 1e-10) return v;
    return v.map((x) => x / norm).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, na = 0, nb = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na  += a[i] * a[i];
      nb  += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0.0;
    return dot / (sqrt(na) * sqrt(nb));
  }

  void dispose() {
    if (_initialized) {
      _detector.close();
      _session?.release();
      _session      = null;
      _initialized  = false;
    }
    _knownPeople      = [];
    _pendingMatchName = null;
    _pendingCount     = 0;
    // BUG-5 FIX: delete the cached temp JPEG so it doesn't accumulate storage.
    if (_tempFilePath != null) {
      try { File(_tempFilePath!).deleteSync(); } catch (_) {}
      _tempFilePath = null;
    }
  }
}
