import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/tts_service.dart';

// 3-step capture: front, left, right — passes List<String> to enter-name screen

class PeopleCaptureScreen extends StatefulWidget {
  const PeopleCaptureScreen({super.key});
  @override
  State<PeopleCaptureScreen> createState() => _PeopleCaptureScreenState();
}

class _PeopleCaptureScreenState extends State<PeopleCaptureScreen> {
  CameraController? _controller;
  final TtsService  _tts = TtsService();

  bool _cameraReady = false;
  bool _capturing   = false;
  String _errorMsg  = '';

  int   _countdown = 0;
  bool  _counting  = false;
  Timer? _timer;

  List<CameraDescription> _cameras  = [];
  int _camIndex = 0;

  // 3-photo state
  int            _step          = 0; // 0=front, 1=left, 2=right
  final List<String?> _paths    = [null, null, null];
  bool           _proceeded     = false; // true once user moves to name screen

  static const _instructions = [
    'Look straight ahead',
    'Turn slightly left',
    'Turn slightly right',
  ];

  static const _ttsInstructions = [
    'Step 1 of 3. Position the face in the oval and look straight ahead. Auto-capture in 5 seconds.',
    'Step 2 of 3. Now turn slightly to the left. Auto-capture in 5 seconds.',
    'Step 3 of 3. Now turn slightly to the right. Auto-capture in 5 seconds.',
  ];

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    await _tts.init();
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() => _errorMsg = 'Camera permission denied.\nGo to App Settings to allow camera.');
      await _tts.speakNow('Camera permission denied. Please open App Settings and allow camera access.');
      return;
    }
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      setState(() => _errorMsg = 'No camera found on this device.');
      return;
    }
    // Prefer front camera for face capture (natural selfie pose)
    final frontIdx = _cameras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.front);
    _camIndex = frontIdx >= 0 ? frontIdx : 0;
    await _initCamera();
  }

  Future<void> _initCamera() async {
    await _controller?.dispose();
    _controller = null;
    if (!mounted) return;
    setState(() { _cameraReady = false; _errorMsg = ''; });

    try {
      final cam  = _cameras[_camIndex.clamp(0, _cameras.length - 1)];
      // medium (720×480) initialises ~2× faster than high and still gives
      // enough detail for LBP face embedding extraction (64×64 crop).
      final ctrl = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) { ctrl.dispose(); return; }
      setState(() { _controller = ctrl; _cameraReady = true; });
      await Future.delayed(const Duration(milliseconds: 400));
      await _tts.speakNow(_ttsInstructions[_step]);
      _startCountdown();
    } catch (e) {
      debugPrint('Camera init error: $e');
      if (mounted) {
        setState(() => _errorMsg = 'Could not open camera.\nTap Try Again.');
        await _tts.speakNow('Camera failed to open. Tap Try Again.');
      }
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() { _countdown = 5; _counting = true; });
    // BUG-C5 FIX: restructured so we never decrement countdown to 0 and then
    // do a second setState — the last tick cancels the timer and goes straight
    // to capture, avoiding a setState-after-dispose window.
    _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        t.cancel();
        if (mounted) setState(() { _counting = false; _countdown = 0; });
        await _capture();
      }
    });
  }

  Future<void> _capture() async {
    _timer?.cancel();
    if (!_cameraReady || _capturing || _controller == null) return;
    setState(() { _capturing = true; _counting = false; _countdown = 0; });
    try {
      final file = await _controller!.takePicture();
      if (!mounted) return;
      _paths[_step] = file.path;
      setState(() => _capturing = false);

      if (_step < 2) {
        final next = _step + 1;
        setState(() => _step = next);
        await _tts.speakNow(_ttsInstructions[next]);
        _startCountdown();
      } else {
        // All 3 captured — go to review
        setState(() {});
        await _tts.speakNow('All 3 photos taken. Tap Save to continue or Retake to start again.');
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        setState(() => _capturing = false);
        await _tts.speakNow('Photo failed. Trying again.');
        _startCountdown();
      }
    }
  }

  void _retakeAll() {
    _timer?.cancel();
    // Delete previously captured files before resetting — otherwise each
    // retake leaves orphaned JPEG files accumulating in app storage.
    for (final path in _paths) {
      if (path != null) try { File(path).deleteSync(); } catch (_) {}
    }
    setState(() {
      _step = 0;
      _paths[0] = null; _paths[1] = null; _paths[2] = null;
      _counting = false; _countdown = 0;
    });
    _tts.speakNow(_ttsInstructions[0]);
    _startCountdown();
  }

  void _proceed() {
    if (_paths.any((p) => p == null)) return;
    _proceeded = true; // photos are being handed off — don't delete them
    _tts.stop();
    _timer?.cancel();
    Navigator.pushNamed(
      context,
      AppRoutes.peopleEnterName,
      arguments: _paths.whereType<String>().toList(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    _tts.dispose();
    // If the user backed out without saving, delete any captured photo files
    // to prevent storage leaks from abandoned capture sessions.
    if (!_proceeded) {
      for (final path in _paths) {
        if (path != null) {
          try { File(path).deleteSync(); } catch (_) {}
        }
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allDone = _paths.every((p) => p != null);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 18, color: Colors.white),
          onPressed: () { _tts.stop(); _timer?.cancel(); Navigator.pop(context); },
        ),
        title: Text(
          allDone ? 'Review Photos' : 'Capture Face ${_step + 1}/3',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        actions: [
          if (_cameras.length > 1 && !allDone && _errorMsg.isEmpty)
            IconButton(
              icon: const Icon(Icons.flip_camera_android, color: AppColors.yellow),
              onPressed: () async {
                _timer?.cancel();
                setState(() { _counting = false; _countdown = 0; });
                _camIndex = (_camIndex + 1) % _cameras.length;
                await _initCamera();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: _errorMsg.isNotEmpty ? _buildError()
             : allDone              ? _buildReview()
             : _buildCamera(),
      ),
    );
  }

  // ── Step progress dots ───────────────────────────────────────────────────────
  Widget _buildStepDots() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (int i = 0; i < 3; i++) ...[
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width:  i == _step ? 24 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: _paths[i] != null
                ? AppColors.green
                : i == _step ? AppColors.yellow : AppColors.greyDark,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        if (i < 2) const SizedBox(width: 6),
      ],
    ]);
  }

  // ── Camera viewfinder ────────────────────────────────────────────────────────
  Widget _buildCamera() => Column(children: [
    Expanded(
      child: _cameraReady
          ? Stack(fit: StackFit.expand, children: [
              CameraPreview(_controller!),
              Center(
                child: Container(
                  width: 230, height: 290,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.yellow.withValues(alpha: 0.8), width: 2.5),
                    borderRadius: BorderRadius.circular(130),
                  ),
                ),
              ),
              if (_counting && _countdown > 0)
                Positioned(top: 16, right: 16,
                  child: Container(
                    width: 58, height: 58,
                    decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                    child: Center(child: Text('$_countdown',
                      style: const TextStyle(color: Colors.black, fontSize: 30, fontWeight: FontWeight.w900))),
                  ),
                ),
              // Step label overlay
              Positioned(bottom: 8, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_instructions[_step],
                      style: const TextStyle(color: AppColors.yellow, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ])
          : const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: AppColors.yellow, strokeWidth: 2),
              SizedBox(height: 16),
              Text('Opening camera...', style: TextStyle(color: AppColors.greyLight, fontSize: 13)),
            ])),
    ),
    Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(children: [
        _buildStepDots(),
        const SizedBox(height: 10),
        Text(
          _counting ? 'Auto-capture in $_countdown s...' : _instructions[_step],
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _counting ? AppColors.yellow : AppColors.greyLight,
            fontSize: 13, fontWeight: _counting ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 18),
        // Shutter button
        GestureDetector(
          onTap: _cameraReady && !_capturing ? _capture : null,
          child: Container(
            width: 76, height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.yellow, width: 4),
            ),
            child: Center(
              child: Container(
                width: 56, height: 56,
                decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
                child: _capturing
                    ? const Padding(padding: EdgeInsets.all(14),
                        child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Icon(Icons.camera_alt, color: Colors.black, size: 28),
              ),
            ),
          ),
        ),
      ]),
    ),
  ]);

  // ── Review all 3 ─────────────────────────────────────────────────────────────
  Widget _buildReview() => Column(children: [
    Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          const Text('3 Photos Captured',
            style: TextStyle(color: AppColors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('All angles recorded for better recognition.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (int i = 0; i < 3; i++)
                Column(children: [
                  Container(
                    width: 90, height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.yellow, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(File(_paths[i]!), fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(_instructions[i],
                    style: const TextStyle(color: AppColors.greyLight, fontSize: 11)),
                ]),
            ],
          ),
        ]),
      ),
    ),
    Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _retakeAll,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.white,
              side: const BorderSide(color: AppColors.greyDark),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 2, child: ElevatedButton.icon(
          onPressed: _proceed,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Save Photos', style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.yellow, foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        )),
      ]),
    ),
  ]);

  // ── Error ────────────────────────────────────────────────────────────────────
  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.camera_alt_outlined, color: AppColors.grey, size: 72),
        const SizedBox(height: 20),
        Text(_errorMsg, textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.white, fontSize: 15, height: 1.6)),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: () async {
            setState(() { _errorMsg = ''; _cameraReady = false; });
            await _setup();
          },
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.yellow, foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: openAppSettings,
          child: const Text('Open App Settings', style: TextStyle(color: AppColors.grey))),
      ]),
    ),
  );
}
