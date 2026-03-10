import 'dart:io';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../services/database_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/tts_service.dart';
import '../../services/shared_stt.dart';
import '../../models/person_model.dart';

class PeopleEnterNameScreen extends StatefulWidget {
  const PeopleEnterNameScreen({super.key});
  @override
  State<PeopleEnterNameScreen> createState() => _PeopleEnterNameScreenState();
}

class _PeopleEnterNameScreenState extends State<PeopleEnterNameScreen> {
  final _ctrl = TextEditingController();
  final _tts  = TtsService();
  bool _isSaving = false;
  List<String> _imagePaths = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is List<String>) {
      _imagePaths = args;
    } else if (args is String) {
      // Backward-compat: single path
      _imagePaths = [args];
    }
  }

  @override
  void initState() {
    super.initState();
    // Speak guidance only — the VoiceTextField mic button is the sole STT
    // entry point.  Previously, _autoStartMic() also called stt.raw.listen()
    // which competed with VoiceTextField's own STT session (dual STT conflict).
    Future.delayed(const Duration(milliseconds: 500), () async {
      await _tts.init();
      await _tts.speakNow(
        'Photos taken. Please enter the person\'s name. '
        'Tap the yellow microphone button and speak clearly.');
    });
  }

  @override
  void dispose() {
    // Stop any active STT session so it doesn't keep running after back-press
    SharedStt.instance.stop();
    _ctrl.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name'), backgroundColor: AppColors.danger));
      return;
    }
    // BUG-12 FIX: guard against empty imagePaths (screen reached without photos).
    // Without this, primaryPath = '' which later causes Image.file('') to crash.
    if (_imagePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No photos found — please retake photos'),
          backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final name        = _ctrl.text.trim();
      final primaryPath = _imagePaths.first;
      final person      = Person(name: name, imagePath: primaryPath, createdAt: DateTime.now());
      final saved       = await DatabaseService.instance.insertPerson(person);

      // Await embedding extraction BEFORE navigating — ensures quality gate
      // runs while the user is still on this screen.
      if (_imagePaths.isNotEmpty && saved.id != null) {
        final ok = await _extractAndSaveEmbedding(saved.id!);
        if (!ok) return; // quality gate failed — stayed on screen
      }

      if (mounted) {
        // Keep MainAI alive; remove all routes between it and personAdded.
        // The extra `|| r.isFirst` guard ensures the stack is never fully
        // emptied if MainAI is somehow missing (defensive safety net).
        Navigator.pushNamedAndRemoveUntil(
          context, AppRoutes.personAdded,
          (r) => r.settings.name == AppRoutes.mainAI || r.isFirst,
          arguments: name,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error saving person'), backgroundColor: AppColors.danger));
    }
  }

  /// Extracts face embeddings from all captured photos and saves them.
  ///
  /// Strategy: store ALL per-photo embeddings concatenated as a single flat
  /// vector (N × 512 values).  During recognition the service scores the live
  /// embedding against each stored 512-d chunk and averages the top-2 scores
  /// (avg-of-top-2).  This requires two stored angles to agree, which sharply
  /// reduces false positives while remaining robust to slight head turns.
  ///
  /// Returns true on success, false if no face was detected (quality gate fail).
  Future<bool> _extractAndSaveEmbedding(int personId) async {
    final embeddings = <List<double>>[];
    final total      = _imagePaths.length;

    for (final path in _imagePaths) {
      final emb = await FaceRecognitionService.instance.extractEmbeddingFromFile(path);
      if (emb != null && emb.isNotEmpty) embeddings.add(emb);
    }

    // ── Quality gate ──────────────────────────────────────────────────────
    if (embeddings.isEmpty) {
      await DatabaseService.instance.deletePerson(personId);
      // Also delete ALL captured photo files — deletePerson only removes the
      // primary path; side-angle photos are not stored in the DB.
      for (final path in _imagePaths) {
        try { File(path).deleteSync(); } catch (_) {}
      }
      await FaceRecognitionService.instance.refreshKnownPeople();
      debugPrint('FaceEmbed: 0/$total photos had a face — registration cancelled');
      await _tts.speakNow(
        'Registration failed. No face was detected in any of the photos. '
        'Please retake in better lighting, closer to the camera.');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No face detected — please retake photos in better light'),
            backgroundColor: AppColors.danger,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return false;
    }

    if (embeddings.length < total) {
      debugPrint('FaceEmbed: ${embeddings.length}/$total photos had a face — partial');
      await _tts.speakNow(
        'Face detected in ${embeddings.length} of $total photos. '
        'Recognition may be less accurate.');
    }

    // ── Concatenate all per-angle embeddings ──────────────────────────────
    // Each embedding is 512 dims. Stored as [emb0 | emb1 | emb2] = 1536 dims.
    // FaceRecognitionService._bestScoreAgainstPerson() knows how to split them.
    final concatenated = _concatEmbeddings(embeddings);
    debugPrint('FaceEmbed: stored ${embeddings.length} angles → '
        '${concatenated.length} dims total (best-of-N matching)');
    await DatabaseService.instance.updateEmbedding(personId, concatenated);
    await FaceRecognitionService.instance.refreshKnownPeople();
    return true;
  }

  /// Concatenates multiple L2-normalised embeddings into one flat vector.
  /// Each embedding retains its own L2 normalisation so per-angle cosine
  /// similarity remains meaningful when compared individually.
  List<double> _concatEmbeddings(List<List<double>> embeddings) {
    final result = <double>[];
    for (final emb in embeddings) {
      result.addAll(emb); // each chunk is already L2-normalised
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: () => Navigator.pop(context)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Spacer(),
          // Show up to 3 captured photo thumbnails
          if (_imagePaths.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _imagePaths.length && i < 3; i++) ...[
                  Container(
                    width: _imagePaths.length == 1 ? 100 : 80,
                    height: _imagePaths.length == 1 ? 100 : 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: i == 0 ? AppColors.yellow : AppColors.greyDark,
                        width: i == 0 ? 3 : 1.5,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.file(File(_imagePaths[i]), fit: BoxFit.cover),
                    ),
                  ),
                  if (i < _imagePaths.length - 1 && i < 2) const SizedBox(width: 8),
                ],
              ],
            )
          else
            Container(
              width: 100, height: 100,
              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              child: const Icon(Icons.person, color: AppColors.grey, size: 52),
            ),
          if (_imagePaths.length > 1) ...[
            const SizedBox(height: 8),
            Text('${_imagePaths.length} photos — better recognition',
              style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 24),
          const Text("What is Their Name?",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.white)),
          const SizedBox(height: 32),
          VoiceTextField(label: 'Name', hint: 'Enter name or tap mic to speak', controller: _ctrl),
          const Spacer(),
          PrimaryButton(text: _isSaving ? 'Saving...' : 'Save Person', onPressed: _isSaving ? () {} : _save),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
