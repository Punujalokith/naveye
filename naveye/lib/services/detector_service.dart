import 'dart:math' as math;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DetectionResult {
  final String label;
  final String rawLabel;
  final double confidence;
  final String direction;
  final String distance;
  final double distanceM;
  final double xCenter;
  final double xMin;
  final double yMin;
  final double xMax;
  final double yMax;
  final bool isWallHeuristic;
  final bool confirmed;

  const DetectionResult({
    required this.label,
    required this.rawLabel,
    required this.confidence,
    required this.direction,
    required this.distance,
    required this.distanceM,
    this.xCenter         = 0.5,
    this.xMin            = 0.1,
    this.yMin            = 0.1,
    this.xMax            = 0.9,
    this.yMax            = 0.9,
    this.isWallHeuristic = false,
    this.confirmed       = true,
  });

  bool get isVeryClose => distanceM < 1.2;

  bool get isVehicle => const {
    'bicycle', 'car', 'motorcycle', 'bus', 'truck', 'train', 'boat', 'airplane'
  }.contains(rawLabel);

  String get distanceSpoken {
    if (distanceM < 0.55) return 'right in front of you';
    if (distanceM < 1.0)  return '${(distanceM * 100).round()} centimetres away';
    if (distanceM < 10.0) {
      final d = (distanceM * 2).round() / 2;
      final n = d == d.truncateToDouble()
          ? '${d.toInt()} metre${d.toInt() == 1 ? "" : "s"}'
          : '$d metres';
      return 'about $n away';
    }
    return 'about ${distanceM.round()} metres away';
  }

  String get announcement {
    if (isWallHeuristic) {
      return distanceM < 0.8
          ? 'Warning — $label directly ahead, stop immediately!'
          : '$label blocking your path, $distanceSpoken';
    }
    if (isVehicle) {
      if (distanceM < 2.0) return 'Warning! $label ahead, $distanceSpoken — stop!';
      if (distanceM < 4.0) return 'Caution — $label ahead, $distanceSpoken';
      return '$label nearby, $distanceSpoken';
    }
    if (isVeryClose) return 'Warning — $label ahead, $distanceSpoken!';
    return '$label, $distanceSpoken';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DetectorService — YOLOv8n COCO via ONNX Runtime
// Model input : float32 BCHW [1, 3, 320, 320], values 0.0–1.0
// Model output: float32 [1, 84, 2100]  (4 box + 80 class scores)
// ─────────────────────────────────────────────────────────────────────────────
class DetectorService {
  OrtSession? _session;
  List<String> _labels   = [];
  bool _isLoaded          = false;
  bool _isProcessing      = false;
  double _thresholdCache  = 0.35; // default Medium — lowered from 0.40 for better recall

  static const int _inputH = 320;
  static const int _inputW = 320;

  // ── All practical COCO classes — full 80-class detection ─────────────────
  // Includes everything a blind person may encounter indoors and outdoors.
  static const Set<String> _allowed = {
    // People
    'person',
    // Vehicles
    'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
    // Traffic
    'traffic light', 'fire hydrant', 'stop sign', 'parking meter',
    // Outdoor/street
    'bench',
    // Animals (trip hazard)
    'bird', 'cat', 'dog', 'horse', 'cow',
    // Carried items
    'backpack', 'umbrella', 'handbag', 'suitcase',
    // Indoor furniture
    'chair', 'couch', 'potted plant', 'bed', 'dining table', 'toilet',
    // Electronics
    'tv', 'laptop', 'keyboard', 'cell phone', 'remote',
    // Kitchen
    'microwave', 'oven', 'toaster', 'sink', 'refrigerator',
    // Small objects (trip/collision risk)
    'bottle', 'cup', 'bowl', 'vase', 'book', 'clock',
    // Misc
    'scissors', 'teddy bear',
  };

  // ── Friendly spoken names ──────────────────────────────────────────────────
  static const Map<String, String> _friendly = {
    'person':        'Person',
    'bicycle':       'Bicycle',
    'car':           'Car',
    'motorcycle':    'Motorcycle',
    'airplane':      'Airplane',
    'bus':           'Bus',
    'train':         'Train',
    'truck':         'Truck',
    'boat':          'Boat',
    'traffic light': 'Traffic Light',
    'fire hydrant':  'Fire Hydrant',
    'stop sign':     'Stop Sign',
    'parking meter': 'Parking Meter',
    'bench':         'Bench',
    'bird':          'Bird',
    'cat':           'Cat',
    'dog':           'Dog',
    'horse':         'Horse',
    'cow':           'Cow',
    'backpack':      'Backpack',
    'umbrella':      'Umbrella',
    'handbag':       'Handbag',
    'suitcase':      'Suitcase',
    'chair':         'Chair',
    'couch':         'Sofa',
    'potted plant':  'Plant',
    'bed':           'Bed',
    'dining table':  'Table',
    'toilet':        'Toilet',
    'tv':            'Television',
    'laptop':        'Laptop',
    'keyboard':      'Keyboard',
    'cell phone':    'Phone',
    'remote':        'Remote',
    'microwave':     'Microwave',
    'oven':          'Oven',
    'toaster':       'Toaster',
    'sink':          'Sink',
    'refrigerator':  'Fridge',
    'bottle':        'Bottle',
    'cup':           'Cup',
    'bowl':          'Bowl',
    'vase':          'Vase',
    'book':          'Book',
    'clock':         'Clock',
    'scissors':      'Scissors',
    'teddy bear':    'Teddy Bear',
  };

  // ── Real-world heights (metres) for monocular distance estimation ──────────
  static const Map<String, double> _heights = {
    'person':        1.70,
    'bicycle':       1.00,
    'car':           1.50,
    'motorcycle':    1.10,
    'airplane':      5.00,
    'bus':           3.00,
    'train':         4.00,
    'truck':         3.50,
    'boat':          1.80,
    'traffic light': 2.50,
    'fire hydrant':  0.75,
    'stop sign':     2.20,
    'parking meter': 1.50,
    'bench':         0.45,
    'bird':          0.25,
    'cat':           0.35,
    'dog':           0.60,
    'horse':         1.60,
    'cow':           1.40,
    'backpack':      0.50,
    'umbrella':      1.00,
    'handbag':       0.35,
    'suitcase':      0.65,
    'chair':         0.90,
    'couch':         0.85,
    'potted plant':  0.40,
    'bed':           0.55,
    'dining table':  0.75,
    'toilet':        0.80,
    'tv':            0.60,
    'laptop':        0.30,
    'keyboard':      0.05,
    'cell phone':    0.15,
    'remote':        0.20,
    'microwave':     0.35,
    'oven':          0.60,
    'toaster':       0.20,
    'sink':          0.90,
    'refrigerator':  1.80,
    'bottle':        0.25,
    'cup':           0.12,
    'bowl':          0.10,
    'vase':          0.30,
    'book':          0.25,
    'clock':         0.30,
    'scissors':      0.18,
    'teddy bear':    0.35,
  };

  // ── Minimum confidence per class ───────────────────────────────────────────
  static const Map<String, double> _minConf = {
    'person':        0.40,
    'car':           0.35,
    'bus':           0.35,
    'truck':         0.35,
    'train':         0.35,
    'bicycle':       0.38,
    'motorcycle':    0.38,
    'stop sign':     0.45,
    'traffic light': 0.40,
    'dog':           0.38,
    'cat':           0.38,
  };

  // ── Minimum bounding-box area (fraction of frame) ─────────────────────────
  static const Map<String, double> _minArea = {
    'car':        0.006,
    'bus':        0.006,
    'truck':      0.006,
    'train':      0.006,
    'motorcycle': 0.008,
    'bicycle':    0.008,
    'airplane':   0.005,
    'boat':       0.005,
    'bottle':     0.003,
    'cup':        0.003,
    'bowl':       0.003,
    'cell phone': 0.003,
    'remote':     0.003,
    'book':       0.005,
  };
  static const double _defaultMinArea = 0.010; // lowered from 0.015

  // ── Confirmation: label → consecutive frame count ─────────────────────────
  final Map<String, int> _confirmCount = {};
  // 2 consecutive frames required before announcing furniture/static objects.
  // Person and vehicles bypass this gate entirely in main_ai_screen.dart.
  static const int _confirmFrames = 2;

  bool get isLoaded => _isLoaded;

  // ──────────────────────────────────────────────────────────────────────────
  Future<void> loadModel() async {
    if (_isLoaded && _session != null) return;
    try {
      OrtEnv.instance.init();

      final modelData = await rootBundle.load('assets/models/detect.onnx');
      final bytes     = modelData.buffer.asUint8List(
          modelData.offsetInBytes, modelData.lengthInBytes);

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(1)
        ..setIntraOpNumThreads(2);
      _session = OrtSession.fromBuffer(bytes, sessionOptions);

      final labelData = await rootBundle.loadString('assets/models/labelmap.txt');
      _labels = labelData.split('\n').where((l) => l.trim().isNotEmpty).toList();

      debugPrint('ONNX COCO model loaded — ${_labels.length} classes, '
          'inputs: ${_session!.inputNames}');
      _isLoaded = true;
    } catch (e) {
      debugPrint('Model load error: $e');
      _isLoaded = false;
    }
  }

  // ── Letterbox: scale to fit 320×320 without distortion, pad black ─────────
  img.Image _letterbox(img.Image src, int targetW, int targetH) {
    final scaleX = targetW / src.width;
    final scaleY = targetH / src.height;
    final scale  = scaleX < scaleY ? scaleX : scaleY;
    final newW   = (src.width  * scale).round();
    final newH   = (src.height * scale).round();
    final scaled = img.copyResize(src, width: newW, height: newH,
        interpolation: img.Interpolation.linear);
    final out    = img.Image(width: targetW, height: targetH);
    img.fill(out, color: out.getColor(0, 0, 0));
    final offX   = (targetW - newW) ~/ 2;
    final offY   = (targetH - newH) ~/ 2;
    img.compositeImage(out, scaled, dstX: offX, dstY: offY);
    return out;
  }

  // ──────────────────────────────────────────────────────────────────────────
  Future<List<DetectionResult>> detect(img.Image image) async {
    if (!_isLoaded || _session == null || _isProcessing) return [];
    _isProcessing = true;
    try {
      final resized   = _letterbox(image, _inputW, _inputH);
      final inputData = _toBCHW(resized);

      final inputTensor = OrtValueTensor.createTensorWithDataList(
        inputData, [1, 3, _inputH, _inputW]);
      final inputs     = {_session!.inputNames.first: inputTensor};
      final runOptions = OrtRunOptions();
      final outputs    = _session!.run(runOptions, inputs);
      inputTensor.release();
      runOptions.release();

      if (outputs.isEmpty || outputs[0] == null) {
        debugPrint('Detector: ONNX returned empty output');
        return [];
      }
      final outTensor = outputs[0]!;
      final nc        = _labels.length; // 80 for COCO

      final raw     = outTensor.value as List;
      final channel = raw[0] as List; // [84, 2100]
      outTensor.release();

      final na = (channel[0] as List).length; // number of anchor candidates

      final List<_RawBox> boxes = [];
      for (int a = 0; a < na; a++) {
        double maxScore = 0.0;
        int    bestCls  = 0;
        for (int c = 0; c < nc; c++) {
          final s = (channel[4 + c] as List)[a] as double;
          if (s > maxScore) { maxScore = s; bestCls = c; }
        }

        if (maxScore < _thresholdCache) continue;
        if (bestCls < 0 || bestCls >= _labels.length) continue;
        final rawLabel = _labels[bestCls].trim().toLowerCase();
        if (!_allowed.contains(rawLabel)) continue;

        final minC = _minConf[rawLabel] ?? _thresholdCache;
        if (maxScore < minC) continue;

        // Coordinates: YOLOv8 ONNX outputs cx,cy,w,h normalised to input size [0–1].
        // Some exports use pixel values — divide by inputW/H to normalise.
        double cx = (channel[0] as List)[a] as double;
        double cy = (channel[1] as List)[a] as double;
        double w  = (channel[2] as List)[a] as double;
        double h  = (channel[3] as List)[a] as double;

        // Auto-detect coordinate space: if any value > 2.0 it is pixel-space.
        if (cx > 2.0 || cy > 2.0 || w > 2.0 || h > 2.0) {
          cx /= _inputW;  cy /= _inputH;
          w  /= _inputW;  h  /= _inputH;
        }

        final area = w * h;
        final minArea = _minArea[rawLabel] ?? _defaultMinArea;
        if (area < minArea) continue;

        boxes.add(_RawBox(
          xMin: (cx - w / 2).clamp(0.0, 1.0),
          yMin: (cy - h / 2).clamp(0.0, 1.0),
          xMax: (cx + w / 2).clamp(0.0, 1.0),
          yMax: (cy + h / 2).clamp(0.0, 1.0),
          score: maxScore, classIdx: bestCls,
        ));
      }

      final kept = _nms(boxes, iouThreshold: 0.45);

      // ── Update confirmation BEFORE building results (fixes off-by-one) ──────
      // This way an object confirmed on frame N is already marked confirmed
      // when _buildResults runs on frame N (not frame N+1).
      _updateConfirmation(kept);

      final results = _buildResults(kept);

      if (results.isNotEmpty) {
        debugPrint('Detector: detected ${results.length} object(s): '
            '${results.map((r) => "${r.label}(${(r.confidence*100).toStringAsFixed(0)}%@${r.distance})").join(", ")}');
      }

      return results;
    } catch (e) {
      debugPrint('Detection error: $e');
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  // ── Update confirmation counters using raw boxes (before building results) ─
  void _updateConfirmation(List<_RawBox> boxes) {
    final seenIndices = boxes.map((b) => b.classIdx).toSet();
    for (int idx = 0; idx < _labels.length; idx++) {
      final label = _labels[idx].trim().toLowerCase();
      if (!_allowed.contains(label)) continue;
      if (seenIndices.contains(idx)) {
        _confirmCount[label] = (_confirmCount[label] ?? 0) + 1;
      } else {
        _confirmCount[label] = 0;
      }
    }
  }

  /// Returns true if [rawLabel] has been confirmed over enough consecutive frames.
  bool isConfirmed(String rawLabel) =>
      (_confirmCount[rawLabel] ?? 0) >= _confirmFrames;

  // ─────────────────────────────────────────────────────────────────────────
  Float32List _toBCHW(img.Image image) {
    final h    = image.height;
    final w    = image.width;
    final data = Float32List(1 * 3 * h * w);
    final rOff = 0 * h * w;
    final gOff = 1 * h * w;
    final bOff = 2 * h * w;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p   = image.getPixel(x, y);
        final idx = y * w + x;
        data[rOff + idx] = p.r.toDouble() / 255.0;
        data[gOff + idx] = p.g.toDouble() / 255.0;
        data[bOff + idx] = p.b.toDouble() / 255.0;
      }
    }
    return data;
  }

  // ─────────────────────────────────────────────────────────────────────────
  List<DetectionResult> _buildResults(List<_RawBox> boxes) {
    final results = <DetectionResult>[];

    for (final b in boxes) {
      if (b.classIdx < 0 || b.classIdx >= _labels.length) continue;
      final rawLabel = _labels[b.classIdx].trim().toLowerCase();
      if (rawLabel.isEmpty || !_allowed.contains(rawLabel)) continue;

      final xMin = b.xMin, yMin = b.yMin, xMax = b.xMax, yMax = b.yMax;
      final boxH = (yMax - yMin).clamp(0.02, 1.0);
      final boxW = (xMax - xMin).clamp(0.02, 1.0);
      final xCtr = (xMin + xMax) / 2;

      if (xCtr < 0.05 || xCtr > 0.95) continue; // extreme edge — relaxed

      final direction = xCtr < 0.33 ? 'left' : xCtr > 0.66 ? 'right' : 'centre';
      final realH     = _heights[rawLabel] ?? 1.0;
      final effH      = (boxH > boxW * 0.6) ? boxH : boxW * 0.6;
      final distM     = (0.866 * realH / effH).clamp(0.3, 15.0);
      final distDisp  = distM < 1.0
          ? '${(distM * 100).round()} cm'
          : distM < 10.0 ? '${distM.toStringAsFixed(1)} m'
                         : '${distM.round()} m';

      final isWall = rawLabel != 'person'
          && rawLabel != 'laptop' && rawLabel != 'cell phone'
          && rawLabel != 'remote' && rawLabel != 'book'
          && boxW > 0.68 && distM < 2.0;

      results.add(DetectionResult(
        label:           _friendly[rawLabel] ?? _cap(rawLabel),
        rawLabel:        rawLabel,
        confidence:      b.score,
        direction:       direction,
        distance:        distDisp,
        distanceM:       distM,
        xCenter:         xCtr,
        xMin: xMin,      yMin: yMin,
        xMax: xMax,      yMax: yMax,
        isWallHeuristic: isWall,
        confirmed:       isConfirmed(rawLabel),
      ));
    }

    // Sort: person first → wall obstacles → vehicles → proximity → confidence
    results.sort((a, b) {
      if (a.rawLabel == 'person' && b.rawLabel != 'person') return -1;
      if (b.rawLabel == 'person' && a.rawLabel != 'person') return  1;
      if (a.isWallHeuristic && !b.isWallHeuristic) return -1;
      if (b.isWallHeuristic && !a.isWallHeuristic) return  1;
      final aVeh = a.isVehicle, bVeh = b.isVehicle;
      if (aVeh && !bVeh) return -1;
      if (bVeh && !aVeh) return  1;
      final dc = a.distanceM.compareTo(b.distanceM);
      return dc != 0 ? dc : b.confidence.compareTo(a.confidence);
    });

    return results;
  }

  // ─────────────────────────────────────────────────────────────────────────
  List<_RawBox> _nms(List<_RawBox> boxes, {double iouThreshold = 0.45}) {
    if (boxes.isEmpty) return [];
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final kept       = <_RawBox>[];
    final suppressed = List.filled(boxes.length, false);

    for (int i = 0; i < boxes.length; i++) {
      if (suppressed[i]) continue;
      kept.add(boxes[i]);
      for (int j = i + 1; j < boxes.length; j++) {
        if (suppressed[j]) continue;
        if (boxes[j].classIdx != boxes[i].classIdx) continue;
        if (_iou(boxes[i], boxes[j]) > iouThreshold) suppressed[j] = true;
      }
    }
    return kept;
  }

  double _iou(_RawBox a, _RawBox b) {
    final ix1  = math.max(a.xMin, b.xMin);
    final iy1  = math.max(a.yMin, b.yMin);
    final ix2  = math.min(a.xMax, b.xMax);
    final iy2  = math.min(a.yMax, b.yMax);
    final inter = math.max(0.0, ix2 - ix1) * math.max(0.0, iy2 - iy1);
    if (inter == 0) return 0;
    final aA = (a.xMax - a.xMin) * (a.yMax - a.yMin);
    final bA = (b.xMax - b.xMin) * (b.yMax - b.yMin);
    return inter / (aA + bA - inter);
  }

  String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Future<void> refreshSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    final level = prefs.getString('ai_sensitivity') ?? 'Medium';
    _thresholdCache = level == 'High' ? 0.25
                    : level == 'Low'  ? 0.50
                    : 0.35;
    debugPrint('Detector: threshold=$_thresholdCache (sensitivity=$level)');
  }

  void resetConfirmation() => _confirmCount.clear();

  void dispose() {
    _session?.release();
    _session = null;
    _isLoaded = false;
    // Do NOT call OrtEnv.instance.release() here — OrtEnv is a global singleton
    // shared with FaceRecognitionService.  Releasing it here would invalidate
    // the face-recognition ONNX session, causing a crash on the next inference.
    // The environment is kept alive for the entire app lifetime.
  }
}

class _RawBox {
  final double xMin, yMin, xMax, yMax, score;
  final int classIdx;
  const _RawBox({
    required this.xMin, required this.yMin,
    required this.xMax, required this.yMax,
    required this.score, required this.classIdx,
  });
}
