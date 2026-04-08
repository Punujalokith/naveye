import 'dart:async' show Timer, unawaited;
import 'dart:io';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/detector_service.dart';
import '../../services/tts_service.dart';
import '../../services/face_recognition_service.dart';
import '../../services/voice_command_service.dart';
import '../../services/shared_stt.dart';
import '../../services/nav_eye_foreground_service.dart';
import '../../services/system_monitor_service.dart';

// ── Fix 1: Top-level YUV→RGB — runs in a background isolate via compute() ───
// Must be top-level (not a method) so Dart can spawn it in a separate isolate.
Map<String, dynamic>? _yuvToRgb(Map<String, dynamic> a) {
  try {
    final yB = a['y'] as Uint8List, uB = a['u'] as Uint8List,
          vB = a['v'] as Uint8List;
    final w = a['w'] as int, h = a['h'] as int;
    final yBpr = a['yBpr'] as int, uBpr = a['uBpr'] as int,
          uBpp = a['uBpp'] as int, rot = a['rot'] as int;

    final rgb = Uint8List(w * h * 3);
    int i = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yv = yB[y * yBpr + x];
        final idx = (y ~/ 2) * uBpr + (x ~/ 2) * uBpp;
        // BUG-37 FIX: bounds check — some Android cameras use non-standard
        // plane strides (e.g. semi-planar NV12/NV21) where idx can exceed the
        // U/V buffer length. Skip silently rather than crash.
        if (idx >= uB.length || idx >= vB.length) { i += 3; continue; }
        final u = uB[idx], v = vB[idx];
        rgb[i++] = (yv + 1.370705 * (v - 128)).clamp(0, 255).toInt();
        rgb[i++] = (yv - 0.337633 * (u - 128) - 0.698001 * (v-128)).clamp(0,255).toInt();
        rgb[i++] = (yv + 1.732446 * (u - 128)).clamp(0, 255).toInt();
      }
    }

    int outW = w, outH = h;
    Uint8List out = rgb;
    if (rot == 90 || rot == 270) {
      final r = Uint8List(w * h * 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final s = (y * w + x) * 3;
          final d = rot == 90 ? (x * h + (h - 1 - y)) * 3
                              : ((w - 1 - x) * h + y) * 3;
          r[d] = rgb[s]; r[d+1] = rgb[s+1]; r[d+2] = rgb[s+2];
        }
      }
      outW = h; outH = w; out = r;
    } else if (rot == 180) {
      final r = Uint8List(w * h * 3);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final s = (y * w + x) * 3;
          final d = ((h-1-y) * w + (w-1-x)) * 3;
          r[d] = rgb[s]; r[d+1] = rgb[s+1]; r[d+2] = rgb[s+2];
        }
      }
      out = r;
    }
    return {'bytes': out, 'w': outW, 'h': outH};
  } catch (_) { return null; }
}

class MainAIScreen extends StatefulWidget {
  const MainAIScreen({super.key});
  @override
  State<MainAIScreen> createState() => _MainAIScreenState();
}

class _MainAIScreenState extends State<MainAIScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cam;
  List<CameraDescription> _cameras = [];
  int _sensorOrientation = 0;
  bool _cameraReady      = false;

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isDetecting   = false;
  bool _isStreaming    = false;
  bool _modelReady    = false;
  bool _voiceActive   = false;

  String _statusText  = 'Initializing...';
  String _detLabel    = '';
  String _direction   = 'CENTRE';
  String _distance    = '';
  double _distanceM   = 100.0;

  // ── Services ──────────────────────────────────────────────────────────────
  final DetectorService     _detector = DetectorService();
  final TtsService          _tts      = TtsService();
  final VoiceCommandService _voice    = VoiceCommandService();
  SystemMonitorService?     _monitor;   // battery + connectivity alerts
  bool _serviceActive = false;          // true when foreground service is running

  // ── Timing / throttle ─────────────────────────────────────────────────────
  DateTime   _lastDetection      = DateTime.now();
  DateTime   _lastFaceCheck      = DateTime.now();
  DateTime   _lastResultTime     = DateTime.now();
  String     _lastAnnouncement   = '';
  double     _lastAnnouncedDist  = 100.0;              // track distance for re-announce
  bool       _vibrationEnabled   = true;
  bool       _busy               = false;              // prevents frame queue buildup
  bool       _pathClearAnnounced = false;

  // ── Per-label cooldown + global minimum gap between announcements ────────
  final Map<String, DateTime> _labelLastAnnounced = {};
  DateTime _lastAnnouncedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _globalCooldownMs  = 3000; // min gap between any two TTS calls
  static const int _perLabelCooldownMs = 9000; // same object repeats every 9 s

  // ── Fix 11: low-light tracking ───────────────────────────────────────────
  bool     _darkWarned     = false;
  DateTime _lastDarkCheck  = DateTime.fromMillisecondsSinceEpoch(0);

  // ── Face recognition cache ────────────────────────────────────────────────
  String?         _cachedName;
  DateTime        _cacheExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  img.Image?      _lastFrame;

  // ── Sequential TTS queue — only ONE pending slot (latest important wins) ──
  String?         _pendingAnnouncement;

  // ── Bounding box overlay ──────────────────────────────────────────────────
  DetectionResult? _topResult;   // carries box coords for the painter

  // ── Camera init guard — prevents concurrent double-initialisation ─────────
  bool _cameraInitializing   = false;
  bool _cameraPermDenied     = false; // true when user denied camera permission

  // ── Voice timeout ─────────────────────────────────────────────────────────
  Timer? _voiceTimeout;

  // ── Pulse animation ───────────────────────────────────────────────────────
  late AnimationController _pulse;
  late Animation<double>   _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _init();
  }

  Future<void> _init() async {
    // ── Parallel startup — TTS, model, camera, prefs all at once ─────────────
    await _tts.init();
    // Start battery + connectivity monitoring right after TTS is ready
    _monitor = SystemMonitorService(_tts);
    // BUG-23 FIX: catch errors from monitor.start() — battery_plus or
    // connectivity_plus can throw on some devices/Android versions.
    unawaited(_monitor!.start().catchError(
        (e) => debugPrint('SystemMonitor start error: $e')));
    await Future.wait([
      _detector.loadModel(),
      _initCamera(),
      _detector.refreshSensitivity(),
      SharedPreferences.getInstance().then((prefs) {
        _vibrationEnabled = prefs.getBool('vibration') ?? true;
      }),
      FaceRecognitionService.instance.init(),
      // NOTE: STT is intentionally NOT initialised here.
      // On Samsung devices (Android 10) calling SpeechToText.initialize() at
      // startup triggers Samsung's speech service to do a background warm-up
      // that fires rapid listening→done cycles every 200 ms even without any
      // explicit listen() call.  We defer STT init until the user actually
      // double-taps to activate voice input (lazy init in VoiceCommandService).
    ]);

    if (mounted) {
      setState(() {
        _modelReady = _detector.isLoaded;
        _statusText = _modelReady
            ? 'Tap camera to start detecting'
            : 'Model load failed — check assets';
      });
    }

    if (_modelReady && mounted) {
      await _tts.speak('NavEye ready. Starting detection automatically.');
      await _startDetectionSilent();
    }
  }

  Future<void> _initCamera() async {
    // Guard: skip if already initializing to prevent concurrent double-init
    if (_cameraInitializing) return;
    _cameraInitializing = true;
    try {
      // ── Speak before the system permission dialog appears ─────────────────
      // Blind users can't see the dialog; announce so they know to tap Allow.
      final camStatus0 = await Permission.camera.status;
      if (!camStatus0.isGranted) {
        await _tts.speak(
          'NavEye needs camera access. '
          'Please tap Allow when the permission dialog appears.');
        await Future.delayed(const Duration(milliseconds: 900));
      }
      // ── Request camera permission before anything else ────────────────────
      final camStatus = await Permission.camera.request();
      if (!camStatus.isGranted) {
        debugPrint('Camera permission denied: $camStatus');
        if (mounted) {
          setState(() {
            _cameraPermDenied = true;
            _statusText = 'Camera permission required';
          });
          await _tts.speakNow(
            'Camera permission denied. '
            'Please open App Settings and allow camera access for NavEye.');
        }
        return;
      }
      if (mounted) setState(() => _cameraPermDenied = false);

      // Dispose existing controller first if any
      if (_cam != null) {
        if (_isStreaming) {
          try { _cam!.stopImageStream(); } catch (_) {}
          _isStreaming = false;
        }
        try { _cam!.dispose(); } catch (_) {}
        _cam = null;
        if (mounted) setState(() => _cameraReady = false);
      }
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final cam = _cameras.first;
      _sensorOrientation = cam.sensorOrientation;
      // ResolutionPreset.medium (720×480) — good preview quality on screen and
      // enough detail for face recognition at 1–3 m. The stream is only active
      // during detection (stopped on toggle-off) so idle GC pressure is zero.
      _cam = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cam!.initialize();
      if (mounted) setState(() => _cameraReady = true);

      // Only pre-start the stream if detection is already active (e.g. on
      // lifecycle resume while detecting). On first launch, detection hasn't
      // started yet — starting the stream here just burns GC with idle frames.
      if (_isDetecting) {
        try {
          await _cam!.startImageStream(_processFrame);
          _isStreaming = true;
          debugPrint('Camera: stream pre-started (detection was active)');
        } catch (e) {
          debugPrint('Camera: startImageStream during init failed: $e');
        }
      } else {
        debugPrint('Camera: stream deferred until detection starts');
      }
    } catch (e) {
      debugPrint('Camera init error: $e');
    } finally {
      _cameraInitializing = false;
    }
  }

  // ── Toggle detection ──────────────────────────────────────────────────────
  Future<void> _toggleDetection() async {
    if (!_cameraReady || !_modelReady || _cam == null) return;
    HapticFeedback.mediumImpact();

    if (_isDetecting) {
      // — STOP —
      setState(() {
        _isDetecting = false;
        _statusText  = 'Tap camera to start detecting';
        _detLabel    = '';
        _distance    = '';
        _distanceM   = 100.0;
        _topResult   = null;
      });
      _cachedName          = null;
      _lastFrame           = null;
      _lastAnnouncement    = '';
      _lastAnnouncedDist   = 100.0;
      _pathClearAnnounced  = false;
      _lastResultTime      = DateTime.now();
      _pendingAnnouncement = null;          // discard any queued speech
      _labelLastAnnounced.clear();
      _detector.resetConfirmation(); // clear confirmation counters on stop
      await _stopStream(); // stop stream to eliminate idle GC frame-buffer churn
      await NavEyeForegroundService.stop();
      if (mounted) setState(() => _serviceActive = false);
      await _tts.speakNow('Detection stopped.');
    } else {
      // — START —
      _pendingAnnouncement = null; // discard stale queued speech from last session
      setState(() {
        _isDetecting = true;
        _statusText  = 'Detecting obstacles...';
        _detLabel    = '';
      });
      await NavEyeForegroundService.start();
      if (mounted) setState(() => _serviceActive = true);
      await _tts.speakNow('Detection started.');
      await _startStream();
    }
  }

  Future<void> _startStream() async {
    if (_isStreaming || _cam == null) return;
    try {
      await _cam!.startImageStream(_processFrame);
      _isStreaming = true;
    } catch (e) {
      debugPrint('startImageStream error: $e');
      _isStreaming = false;
      if (mounted) {
        setState(() {
          _isDetecting = false;
          _statusText  = 'Camera error — tap to retry';
        });
      }
    }
  }

  Future<void> _stopStream() async {
    if (!_isStreaming || _cam == null) return;
    try { await _cam!.stopImageStream(); } catch (_) {}
    _isStreaming = false;
  }

  // Fix 5: start detection without playing TTS (used for auto-start on launch)
  Future<void> _startDetectionSilent() async {
    if (!_cameraReady || !_modelReady || _cam == null || _isDetecting) return;
    _pendingAnnouncement = null; // discard any stale queued speech
    if (mounted) {
      setState(() {
        _isDetecting = true;
        _statusText  = 'Detecting obstacles...';
        _detLabel    = '';
      });
    }
    await NavEyeForegroundService.start();
    if (mounted) setState(() => _serviceActive = true);
    _lastResultTime = DateTime.now();
    // Stream was started during _initCamera (single-configure optimisation).
    // If for any reason it isn't running yet, start it now.
    if (!_isStreaming) await _startStream();
  }

  Future<void> _processFrame(CameraImage frame) async {
    // Drop frames if not detecting or model not ready yet — stream stays warm
    if (!_isDetecting || !_modelReady) return;
    if (_busy) return;
    final now = DateTime.now();
    if (now.difference(_lastDetection).inMilliseconds < 1000) return;
    _lastDetection = now;
    _busy = true;

    try {
      // ── Drain pending announcement when TTS just finished ─────────────────
      if (_pendingAnnouncement != null && !_tts.isSpeaking) {
        final msg = _pendingAnnouncement!;
        _pendingAnnouncement = null;
        await _tts.announce(msg);
      }

      // YUV conversion off the UI thread
      final raw = await compute(_yuvToRgb, {
        'y': Uint8List.fromList(frame.planes[0].bytes),
        'u': Uint8List.fromList(frame.planes[1].bytes),
        'v': Uint8List.fromList(frame.planes[2].bytes),
        'w': frame.width,   'h': frame.height,
        'yBpr': frame.planes[0].bytesPerRow,
        'uBpr': frame.planes[1].bytesPerRow,
        'uBpp': frame.planes[1].bytesPerPixel ?? 2,
        'rot':  _sensorOrientation,
      });
      if (raw == null || !mounted) return;
      final image = img.Image.fromBytes(
        width:  raw['w'] as int,
        height: raw['h'] as int,
        bytes:  (raw['bytes'] as Uint8List).buffer,
        format: img.Format.uint8,
        numChannels: 3,
      );
      _lastFrame   = image;

      // Fix 11: low-light check (sample centre pixels)
      if (now.difference(_lastDarkCheck).inSeconds >= 5) {
        _lastDarkCheck = now;
        final cx = image.width ~/ 2, cy = image.height ~/ 2;
        int brightness = 0, cnt = 0;
        for (int y = cy - 60; y < cy + 60; y += 6) {
          for (int x = cx - 60; x < cx + 60; x += 6) {
            if (y < 0 || y >= image.height || x < 0 || x >= image.width) continue;
            final p = image.getPixel(x, y);
            brightness += ((p.r + p.g + p.b) ~/ 3);
            cnt++;
          }
        }
        final avg = cnt > 0 ? brightness ~/ cnt : 255;
        if (avg < 38) {
          if (!_darkWarned) {
            _darkWarned = true;
            await _tts.announce(
                'Warning: too dark for reliable detection. '
                'Please move to a brighter area.');
          }
          return; // skip detection in darkness
        } else {
          _darkWarned = false;
        }
      }

      final results = await _detector.detect(image);
      if (!mounted) return;

      // ── Nothing detected ─────────────────────────────────────────────────
      if (results.isEmpty) {
        if (mounted) {
          setState(() {
            _detLabel   = ''; _direction = 'CENTRE';
            _distance   = ''; _distanceM = 100.0;
            _topResult  = null;
          });
        }
        // Announce clear path after 5 s of no detections (faster feedback)
        if (!_pathClearAnnounced &&
            now.difference(_lastResultTime).inSeconds >= 5) {
          _pathClearAnnounced = true;
          _labelLastAnnounced.clear(); // reset so next object announces immediately
          await _tts.announce('Path ahead is clear.');
          if (_serviceActive) unawaited(NavEyeForegroundService.clearDetection());
        }
        return;
      }

      _lastResultTime     = now;
      _pathClearAnnounced = false;

      // ── Direction → natural phrase ────────────────────────────────────────
      String naturalDir(String d) =>
          d == 'left' ? 'to your left' : d == 'right' ? 'to your right' : 'in front of you';

      // Navigation hint based on object position and distance
      String navHint(String d, double dist, bool isWall) {
        if (isWall || dist > 5.0) return '';
        if (dist < 0.8)   return ' Stop!';
        if (d == 'left')  return ' Move right to pass.';
        if (d == 'right') return ' Move left to pass.';
        return ' Slow down.';
      }

      // ── Pick most-centred object (wall/obstacle always wins) ─────────────
      final top = results.firstWhere(
        (r) => r.isWallHeuristic,
        orElse: () => results.reduce(
          (a, b) => (a.xCenter-0.5).abs() <= (b.xCenter-0.5).abs() ? a : b,
        ),
      );

      String label        = top.label;
      String announcement = top.announcement;

      // ── Confirmation gate — skip unconfirmed detections (reduces false alerts)
      // Exceptions: always announce person, vehicles, or anything very close on first frame.
      if (!top.confirmed &&
          top.rawLabel != 'person' &&
          !top.isVehicle &&
          !top.isVeryClose) { return; }

      // ── Person — crop bounding box → face recognition ─────────────────────
      if (top.rawLabel == 'person') {
        if (_cachedName != null && now.isBefore(_cacheExpiry)) {
          label        = _cachedName!;
          announcement = 'That is $_cachedName, ${naturalDir(top.direction)}, '
              '${top.distanceSpoken}';
        } else if (now.difference(_lastFaceCheck).inMilliseconds >= 1500) {
          _lastFaceCheck = now;
          // Pass the FULL camera frame + YOLO person bounding box (normalised).
          // ML Kit detects faces at full resolution — much more accurate than
          // passing a pre-cropped region, which caused the wrong face (or no
          // face) to be selected when the crop was too small or misaligned.
          final match = await FaceRecognitionService.instance
              .recogniseInFrame(
                image,
                pxMin: top.xMin, pyMin: top.yMin,
                pxMax: top.xMax, pyMax: top.yMax,
              );
          if (match != null) {
            _cachedName  = match.name;
            _cacheExpiry = now.add(const Duration(seconds: 12));
            label        = match.name;
            announcement = 'That is ${match.name}, ${naturalDir(top.direction)}, '
                '${top.distanceSpoken}';
          } else {
            _cachedName  = null;
            // FIX-D: Always announce "unknown person" so blind user knows someone
            // is there even when not recognised. Previously only said "not recognised"
            // when very close — now says it at any distance so no one is silently ignored.
            label        = 'Person';
            announcement = 'Unknown person ${naturalDir(top.direction)}, ${top.distanceSpoken}';
          }
        } else {
          if (_cachedName != null) {
            label        = _cachedName!;
            announcement = 'That is $_cachedName, ${naturalDir(top.direction)}, '
                '${top.distanceSpoken}';
          } else {
            label        = 'Person';
            announcement = 'Unknown person ${naturalDir(top.direction)}, ${top.distanceSpoken}';
          }
        }
      } else if (top.isVehicle) {
        // Vehicles — richer directional warning, no face check
        _cachedName  = null;
        if (top.distanceM < 2.0) {
          announcement = 'Warning! ${top.label} ${naturalDir(top.direction)}, '
              '${top.distanceSpoken} — stop!';
        } else if (top.distanceM < 4.0) {
          announcement = 'Caution — ${top.label} ${naturalDir(top.direction)}, '
              '${top.distanceSpoken}. Be careful.';
        } else {
          announcement = '${top.label} ${naturalDir(top.direction)}, ${top.distanceSpoken}';
        }
      } else {
        _cachedName  = null;
        announcement += navHint(top.direction, top.distanceM, top.isWallHeuristic);
      }

      // Secondary danger — any very-close object that isn't the primary result
      final DetectionResult? danger = results.cast<DetectionResult?>().firstWhere(
        (r) => r != top && r!.distanceM < 1.0 && !r.isWallHeuristic,
        orElse: () => null,
      );
      final secondaryAlert = danger != null
          ? ' Also — warning, ${danger.label} ${naturalDir(danger.direction)}, '
            '${danger.distanceSpoken}!'
          : '';

      if (mounted) {
        setState(() {
          _detLabel  = label;
          _direction = top.direction.toUpperCase();
          _distance  = top.distance;
          _distanceM = top.distanceM;
          _topResult = top; // drives the bounding box painter
        });
      }
      // Update persistent notification text so lock-screen shows current obstacle
      if (_serviceActive) {
        unawaited(NavEyeForegroundService.update(
          label: label, distance: top.distance));
      }

      // Haptic patterns by object type and distance
      if (_vibrationEnabled && await Vibration.hasVibrator() == true) {
        if (top.isVehicle && top.distanceM < 4.0) {
          // Aggressive long-short-long — vehicle hazard
          Vibration.vibrate(pattern: [0, 300, 100, 150, 100, 300]);
        } else if (top.rawLabel == 'person') {
          // Two short pulses — person detected
          Vibration.vibrate(pattern: [0, 80, 120, 80]);
        } else if (top.distanceM < 0.6) {
          // Rapid triple pulse — immediate danger
          Vibration.vibrate(pattern: [0, 200, 80, 200, 80, 200]);
        } else if (top.isVeryClose) {
          // Single long pulse — very close obstacle
          Vibration.vibrate(duration: 500);
        } else {
          // Short tap — normal detection
          Vibration.vibrate(duration: 80);
        }
      }

      // ── Cooldown gate — prevents non-stop TTS ────────────────────────────
      //
      // Per-label cooldowns (adaptive to distance):
      //   < 0.8 m (immediate danger) : 4 s minimum per label
      //   < 1.2 m (danger proximity) : 7 s minimum per label
      //   normal                     : 9 s minimum per label (global default)
      //
      // Global minimum: 3 s between ANY two TTS calls.
      //
      // ⚠ Bug fixed: previously `immediateDanger` bypassed ALL cooldowns,
      //   causing non-stop TTS every detection frame when an object was closer
      //   than 0.8 m. Now even immediate danger respects a per-label minimum.
      //
      // ⚠ Bug fixed: `warnThreshold` oscillated at the 1.2 m boundary
      //   (object at 1.18 m → 1.23 m → 1.18 m... triggered every cycle).
      //   Fixed by using 1.5 m hysteresis: must retreat ABOVE 1.5 m before
      //   the "entered danger zone" alert can re-fire for the same label.
      final lastForLabel   = _labelLastAnnounced[label]
          ?? DateTime.fromMillisecondsSinceEpoch(0);
      final sinceThisLabel = now.difference(lastForLabel).inMilliseconds;
      final sinceGlobal    = now.difference(_lastAnnouncedAt).inMilliseconds;

      // Immediate danger — object < 0.8 m
      final immediateDanger = top.distanceM < 0.8;

      // Adaptive per-label cooldown (generous enough to stop spam)
      final effectivePerLabel = immediateDanger    ? 4000   // 4 s even for very close
                              : top.distanceM < 1.2 ? 7000  // 7 s in danger zone
                              : _perLabelCooldownMs;         // 9 s normally

      // Newly entered danger zone — use 1.5 m hysteresis to stop oscillation.
      // The object must have been ABOVE 1.5 m (not just 1.2 m) before the
      // "entered danger zone" announcement can fire again for this label.
      final warnThreshold = _lastAnnouncedDist >= 1.5 && top.distanceM < 1.2;

      // Master gate — at least one condition must be true AND global minimum met
      final doAnnounce = sinceGlobal >= _globalCooldownMs &&
          (warnThreshold || sinceThisLabel >= effectivePerLabel);

      if (doAnnounce) {
        final full = announcement + secondaryAlert;
        _labelLastAnnounced[label] = now;
        _lastAnnouncedAt           = now;
        _lastAnnouncement          = full;
        _lastAnnouncedDist         = top.distanceM;

        if (immediateDanger) {
          // Danger interrupts whatever is playing
          _pendingAnnouncement = null;
          await _tts.announce(full);
        } else if (!_tts.isSpeaking) {
          await _tts.announce(full);
        } else {
          // TTS busy — queue single pending slot (latest wins)
          _pendingAnnouncement = full;
        }
      }
    } catch (e) {
      debugPrint('Frame error: $e');
    } finally {
      _busy = false;
    }
  }

  // ── Voice commands ────────────────────────────────────────────────────────
  void _resetVoiceState() {
    _voiceTimeout?.cancel();
    _voiceTimeout = null;
    _voice.stopListening(); // stop mic if still open
    _tts.unmute();
    if (mounted) setState(() => _voiceActive = false);
  }

  Future<void> _startVoiceListen() async {
    // Always cancel any pending timeout first to avoid a race where the old
    // timer fires during the new listen session and resets voice state.
    _voiceTimeout?.cancel();
    _voiceTimeout = null;

    // Tap again while active → cancel (toggle off)
    if (_voiceActive) {
      _resetVoiceState();
      await _tts.speakNow('Cancelled.');
      return;
    }

    await _tts.stop();
    HapticFeedback.heavyImpact();
    setState(() => _voiceActive = true);

    // ── Audio confirmation ────────────────────────────────────────────────────
    // Tell the blind user the mic is now open BEFORE muting detection TTS.
    // speakNow ignores mute so it always fires.
    // FIX-3: richer prompt so user knows exactly what to say.
    await _tts.speakNow('Listening — say start, stop, or help');
    // FIX-1: gap raised 700ms → 1300ms.
    // "Listening — say start, stop, or help" takes ~1.1 s to speak at medium
    // rate. At 700 ms the mic opened while TTS was still talking → error_audio
    // → STT died instantly → "Sorry, not heard" every time.
    await Future.delayed(const Duration(milliseconds: 1300));

    _tts.mute(); // mute obstacle TTS while mic is active

    // Safety: auto-cancel after 12 s if no command received
    _voiceTimeout?.cancel();
    _voiceTimeout = Timer(const Duration(seconds: 12), () {
      _resetVoiceState();
      _tts.speakNow('No command heard.');
    });

    if (!_voiceActive) return; // was cancelled during the delay

    await _voice.startListening((cmd) async {
      _resetVoiceState();
      // Audio feedback on result
      if (cmd != VoiceCommand.unknown) {
        await _tts.speakNow('Got it.');
      } else {
        await _tts.speakNow('Sorry, not heard. Try again.');
      }
      await _handleCmd(cmd);
    });
  }

  Future<void> _handleCmd(VoiceCommand cmd) async {
    switch (cmd) {
      case VoiceCommand.start:
        if (!_isDetecting) await _toggleDetection();
        break;
      case VoiceCommand.stop:
        if (_isDetecting) await _toggleDetection();
        break;
      case VoiceCommand.repeat:
        await _tts.speakNow(
          _lastAnnouncement.isNotEmpty ? _lastAnnouncement : 'Nothing to repeat.');
        break;
      case VoiceCommand.whoIsThis:
        await _tts.speakNow('Checking who is in front of you.');
        _cachedName    = null;
        _lastFaceCheck = DateTime.fromMillisecondsSinceEpoch(0);

        img.Image? checkFrame = _lastFrame;

        // Fix 6: if detection is stopped, take a single snapshot
        if (checkFrame == null && _cam != null && _cameraReady && !_isStreaming) {
          try {
            final xFile = await _cam!.takePicture();
            final bytes = await File(xFile.path).readAsBytes();
            checkFrame  = img.decodeImage(bytes);
            await File(xFile.path).delete();
          } catch (e) {
            debugPrint('Snapshot error: $e');
          }
        }

        if (checkFrame != null) {
          final match = await FaceRecognitionService.instance
              .recogniseInFrame(checkFrame);
          if (match != null) {
            _cachedName  = match.name;
            _cacheExpiry = DateTime.now().add(const Duration(seconds: 15));
            await _tts.speakNow('That is ${match.name}.');
          } else {
            await _tts.speakNow(
                'No known face detected. This person is unknown.');
          }
        } else {
          await _tts.speakNow('Could not capture an image. Please try again.');
        }
        break;
      case VoiceCommand.openSettings:
        await _tts.speakNow('Opening settings.');
        if (mounted) {
          await Navigator.pushNamed(context, AppRoutes.settings);
          await _detector.refreshSensitivity();
          await _tts.init();
          final p = await SharedPreferences.getInstance();
          if (mounted) setState(() => _vibrationEnabled = p.getBool('vibration') ?? true);
        }
        break;
      case VoiceCommand.openPeople:
        _showPeopleMenu();
        break;
      case VoiceCommand.help:
        await _tts.speakNow(
          'Available commands: Start, Stop, Repeat, Who is this, People, Settings, Help.');
        break;
      case VoiceCommand.unknown:
        await _tts.speakNow('Command not recognised. Say Help for a list of commands.');
        break;
    }
  }

  // ── People menu ───────────────────────────────────────────────────────────
  void _showPeopleMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.greyDark,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('People',
                style: TextStyle(color: AppColors.white, fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            _MenuTile(
              icon: Icons.person_add_alt_1, label: 'Add New Person',
              sub: 'Capture a face to recognise later',
              color: AppColors.yellow,
              onTap: () async {
                Navigator.pop(context);
                // Stop the back-camera stream before the capture screen opens
                // its front camera — prevents dual-camera contention on
                // Samsung devices which causes freezing or slow init.
                await _stopStream();           // BUG-22 FIX: use helper consistently
                await Navigator.pushNamed(context, AppRoutes.peopleCapture);
                await FaceRecognitionService.instance.refreshKnownPeople();
                // Restart the stream now that capture is done.
                if (mounted && _isDetecting && _cam != null && !_isStreaming) {
                  await _startStream();
                }
              },
            ),
            const SizedBox(height: 10),
            _MenuTile(
              icon: Icons.people_alt_outlined, label: 'View / Manage People',
              sub: 'See and delete saved faces',
              color: AppColors.green,
              onTap: () async {
                Navigator.pop(context);
                await Navigator.pushNamed(context, AppRoutes.peopleList);
                await FaceRecognitionService.instance.refreshKnownPeople();
              },
            ),
          ]),
        ),
      ),
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  bool _wasPausedByLifecycle = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasPausedByLifecycle = true;
      // ── If the foreground service is running, keep camera alive ─────────────
      // The service holds the process alive; detection continues in background
      // so a blind user gets TTS alerts even when screen is locked.
      if (_serviceActive) {
        debugPrint('Lifecycle: paused — foreground service active, camera kept alive');
        return;
      }
      // ── No service — dispose camera to free resources ────────────────────
      if (_cam == null) return;
      if (mounted) setState(() => _cameraReady = false);
      if (_isStreaming) {
        try { _cam!.stopImageStream(); } catch (_) {}
        _isStreaming = false;
      }
      try { _cam!.dispose(); } catch (_) {}
      _cam = null;
      _cameraInitializing = false; // allow re-init on resume
    } else if (state == AppLifecycleState.resumed &&
               _wasPausedByLifecycle) {
      _wasPausedByLifecycle = false;
      if (!SharedStt.instance.available) SharedStt.instance.reset();
      if (_cam != null) {
        // Camera was kept alive by the foreground service — just refresh UI
        if (mounted) setState(() => _cameraReady = true);
        debugPrint('Lifecycle: resumed — camera still alive, no re-init needed');
      } else {
        // Camera was disposed — full re-initialise
        _initCamera().then((_) {
          if (_isDetecting && !_isStreaming && mounted) _startStream();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceTimeout?.cancel();
    _pulse.dispose();
    _monitor?.dispose();
    unawaited(NavEyeForegroundService.stop()); // fire-and-forget stop
    if (_isStreaming) {
      try { _cam?.stopImageStream(); } catch (_) {}
      _isStreaming = false;
    }
    _cam?.dispose();
    _detector.dispose();
    _tts.dispose();
    _voice.dispose();
    // Do NOT call FaceRecognitionService.instance.dispose() here.
    // The service is a singleton shared by the whole app; disposing it from
    // a screen that can be re-created (e.g. after navigator.pop) would null
    // the ONNX session, causing a crash on the next recogniseInFrame() call.
    // The ONNX session is kept alive for the app's lifetime.
    super.dispose();
  }

  // ── Colour helpers ────────────────────────────────────────────────────────
  Color get _distColor {
    if (_distanceM < 1.2) return const Color(0xFFEF5350);
    if (_distanceM < 3.0) return const Color(0xFFFF9800);
    return AppColors.green;
  }

  Color get _borderColor {
    if (!_isDetecting) return AppColors.greyDark;
    if (_detLabel.isNotEmpty && _distanceM < 1.2) return const Color(0xFFEF5350);
    return AppColors.green;
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [

          // Status bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(
                  _isDetecting ? Icons.radar : Icons.search_outlined,
                  color: _isDetecting ? AppColors.green : AppColors.grey, size: 17),
                const SizedBox(width: 8),
                Expanded(child: Text(_statusText,
                    style: const TextStyle(color: AppColors.greyLight, fontSize: 13))),
                if (_isDetecting)
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, __) => Opacity(
                      opacity: _pulseAnim.value,
                      child: Container(width: 8, height: 8,
                          decoration: const BoxDecoration(
                              color: AppColors.green, shape: BoxShape.circle)),
                    ),
                  ),
              ]),
            ),
          ),

          // Camera area — full gesture control for blind users
          //   Single tap    → toggle detection on / off
          //   Double tap    → activate voice command
          //   Long press    → repeat last announcement
          //   Swipe up      → identify person in front
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: _toggleDetection,
                onDoubleTap: () {
                  HapticFeedback.heavyImpact();
                  _startVoiceListen();
                },
                onLongPress: () {
                  HapticFeedback.heavyImpact();
                  final msg = _lastAnnouncement.isNotEmpty
                      ? _lastAnnouncement
                      : 'Nothing to repeat yet.';
                  _tts.speakNow(msg);
                },
                onVerticalDragEnd: (details) {
                  // Swipe up (negative velocity = upward)
                  if ((details.primaryVelocity ?? 0) < -400) {
                    HapticFeedback.mediumImpact();
                    _handleCmd(VoiceCommand.whoIsThis);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderColor, width: 2.0),
                    boxShadow: _isDetecting && _distanceM < 1.2
                        ? [BoxShadow(
                            color: const Color(0xFFEF5350).withValues(alpha: 0.3),
                            blurRadius: 12, spreadRadius: 2)]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _cameraReady && _cam != null
                        ? Stack(fit: StackFit.expand, children: [
                            CameraPreview(_cam!),

                            // ── White viewfinder / focus frame ────────────
                            // Always shown while detecting so the user (or a
                            // helper) knows which zone the AI is focusing on.
                            // Fades to a ghost when the detection box is active.
                            if (_isDetecting)
                              CustomPaint(
                                size: Size.infinite,
                                painter: _ViewfinderPainter(
                                    hasDetection: _topResult != null),
                              ),

                            // ── Bounding box overlay ──────────────────────
                            if (_isDetecting && _topResult != null)
                              AnimatedBuilder(
                                animation: _pulseAnim,
                                builder: (_, __) => CustomPaint(
                                  size: Size.infinite,
                                  painter: _DetectionBoxPainter(
                                    result:     _topResult!,
                                    pulseValue: _pulseAnim.value,
                                  ),
                                ),
                              ),

                            // Idle overlay
                            if (!_isDetecting)
                              Container(
                                color: Colors.black54,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 80, height: 80,
                                      decoration: BoxDecoration(
                                        color: AppColors.yellow.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: AppColors.yellow, width: 2),
                                      ),
                                      child: const Icon(Icons.touch_app,
                                          color: AppColors.yellow, size: 42),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('Tap to Start Detection',
                                        style: TextStyle(color: AppColors.white,
                                            fontSize: 20, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 8),
                                    Text(
                                      _modelReady ? 'AI model ready' : 'Model not loaded',
                                      style: TextStyle(
                                        color: _modelReady ? AppColors.green : AppColors.danger,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    // Gesture hint cards
                                    _GestureHint(icon: Icons.touch_app,   label: 'Tap',         hint: 'Start / Stop detection'),
                                    const SizedBox(height: 4),
                                    _GestureHint(icon: Icons.mic,          label: 'Double-tap',  hint: 'Voice command'),
                                    const SizedBox(height: 4),
                                    _GestureHint(icon: Icons.replay,       label: 'Long press',  hint: 'Repeat last alert'),
                                    const SizedBox(height: 4),
                                    _GestureHint(icon: Icons.swipe_up,     label: 'Swipe up',    hint: 'Identify person'),
                                  ],
                                ),
                              ),

                            // ── LISTENING overlay ─────────────────────────
                            // Shown regardless of detection state so the user
                            // ALWAYS sees a clear red banner when the mic is on.
                            if (_voiceActive)
                              Positioned(
                                top: 8, left: 0, right: 0,
                                child: Center(
                                  child: AnimatedBuilder(
                                    animation: _pulseAnim,
                                    builder: (_, __) => Opacity(
                                      opacity: 0.78 + 0.22 * _pulseAnim.value,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 9),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE53935),
                                          borderRadius: BorderRadius.circular(26),
                                          boxShadow: [BoxShadow(
                                            color: const Color(0xFFE53935)
                                                .withValues(alpha: 0.55),
                                            blurRadius: 16, spreadRadius: 2)],
                                        ),
                                        child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          Icon(Icons.mic,
                                              color: Colors.white, size: 17),
                                          SizedBox(width: 7),
                                          Text('LISTENING...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.6,
                                              )),
                                        ]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            if (_isDetecting) ...[
                              // LIVE badge
                              Positioned(
                                top: 12, left: 12,
                                child: AnimatedBuilder(
                                  animation: _pulseAnim,
                                  builder: (_, __) => Opacity(
                                    opacity: 0.7 + 0.3 * _pulseAnim.value,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                          color: AppColors.green,
                                          borderRadius: BorderRadius.circular(20)),
                                      child: const Row(children: [
                                        Icon(Icons.fiber_manual_record,
                                            color: Colors.white, size: 9),
                                        SizedBox(width: 4),
                                        Text('LIVE', style: TextStyle(
                                            color: Colors.white, fontSize: 11,
                                            fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),

                              // Very close warning badge
                              if (_detLabel.isNotEmpty && _distanceM < 1.2)
                                Positioned(
                                  top: 12, right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFEF5350),
                                        borderRadius: BorderRadius.circular(20)),
                                    child: const Row(children: [
                                      Icon(Icons.warning_amber_rounded,
                                          color: Colors.white, size: 14),
                                      SizedBox(width: 4),
                                      Text('VERY CLOSE', style: TextStyle(
                                          color: Colors.white, fontSize: 11,
                                          fontWeight: FontWeight.w800)),
                                    ]),
                                  ),
                                ),

                              // Detection result overlay (NO confidence %)
                              if (_detLabel.isNotEmpty)
                                Positioned(
                                  bottom: 12, left: 12, right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.88),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: _distColor.withValues(alpha: 0.4), width: 1.5),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_detLabel,
                                            style: const TextStyle(
                                                color: AppColors.yellow,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 8),
                                        Row(children: [
                                          // Distance pill
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _distColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(
                                                  color: _distColor.withValues(alpha: 0.6)),
                                            ),
                                            child: Row(children: [
                                              Icon(
                                                _distanceM < 1.2
                                                    ? Icons.warning_amber_rounded
                                                    : Icons.straighten,
                                                color: _distColor, size: 13),
                                              const SizedBox(width: 4),
                                              Text(_distance,
                                                  style: TextStyle(
                                                      color: _distColor,
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700)),
                                            ]),
                                          ),
                                          const SizedBox(width: 10),
                                          // Direction pill
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.greyDark,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Row(children: [
                                              Icon(
                                                _direction == 'LEFT'
                                                    ? Icons.arrow_back
                                                    : _direction == 'RIGHT'
                                                        ? Icons.arrow_forward
                                                        : Icons.arrow_upward,
                                                color: AppColors.white, size: 12),
                                              const SizedBox(width: 4),
                                              Text(_direction,
                                                  style: const TextStyle(
                                                      color: AppColors.white,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600)),
                                            ]),
                                          ),
                                        ]),
                                      ],
                                    ),
                                  ),
                                ),

                              // Scanning spinner (no detection yet)
                              if (_detLabel.isEmpty)
                                Positioned(
                                  bottom: 12, left: 12, right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Row(children: [
                                      SizedBox(width: 14, height: 14,
                                          child: CircularProgressIndicator(
                                              color: AppColors.green, strokeWidth: 2)),
                                      SizedBox(width: 10),
                                      Text('Scanning for obstacles...',
                                          style: TextStyle(
                                              color: AppColors.greyLight, fontSize: 13)),
                                    ]),
                                  ),
                                ),
                            ],
                          ])
                        : _cameraPermDenied
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.no_photography_outlined,
                                    color: AppColors.danger, size: 60),
                                const SizedBox(height: 16),
                                const Text('Camera Permission Required',
                                    style: TextStyle(
                                        color: AppColors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                const Text(
                                  'NavEye needs camera access\nto detect obstacles.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: AppColors.grey, fontSize: 13, height: 1.5)),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await openAppSettings();
                                  },
                                  icon: const Icon(Icons.settings, size: 16),
                                  label: const Text('Open App Settings',
                                      style: TextStyle(fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.yellow,
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextButton(
                                  onPressed: () {
                                    setState(() => _cameraPermDenied = false);
                                    _initCamera();
                                  },
                                  child: const Text('Retry',
                                      style: TextStyle(color: AppColors.grey)),
                                ),
                              ],
                            )
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                    color: AppColors.yellow, strokeWidth: 2),
                                SizedBox(height: 16),
                                Text('Initializing camera...',
                                    style: TextStyle(
                                        color: AppColors.greyLight, fontSize: 14)),
                              ],
                            ),
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom bar: People | MIC | Settings ────────────────────────────
          // The mic button is centred and large so it is impossible to miss.
          // RED  + pulsing glow + "ON"  label = actively listening
          // GREY + no glow     + "MIC" label = off / ready to tap
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [

              // ── People ──────────────────────────────────────────────────────
              Expanded(
                child: GestureDetector(
                  onTap: _showPeopleMenu,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.yellow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.people, color: Colors.black, size: 20),
                      SizedBox(height: 4),
                      Text('People', style: TextStyle(
                          color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // ── Microphone ─────────────────────────────────────────────────
              // Large centred circle — unmistakably ON (red) or OFF (grey).
              GestureDetector(
                onTap: _startVoiceListen,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) {
                    final active = _voiceActive;
                    // RED when listening, dark grey when off
                    const onColor  = Color(0xFFE53935); // red
                    const offColor = AppColors.surface;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color:  active ? onColor  : offColor,
                        shape:  BoxShape.circle,
                        border: Border.all(
                          color: active ? onColor : AppColors.greyDark,
                          width: 3,
                        ),
                        boxShadow: active
                            ? [BoxShadow(
                                color: onColor.withValues(
                                    alpha: 0.30 + 0.35 * _pulseAnim.value),
                                blurRadius: 18 + 12 * _pulseAnim.value,
                                spreadRadius: 3)]
                            : null,
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                          active ? Icons.mic : Icons.mic_none,
                          color:  active ? Colors.white : AppColors.grey,
                          size:   active ? 30 : 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          active ? 'STOP' : 'SPEAK',
                          style: TextStyle(
                            color:      active ? Colors.white : AppColors.grey,
                            fontSize:   9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),

              const SizedBox(width: 10),

              // ── Settings ───────────────────────────────────────────────────
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    HapticFeedback.lightImpact();
                    await Navigator.pushNamed(context, AppRoutes.settings);
                    await _detector.refreshSensitivity();
                    await _tts.init();
                    final p = await SharedPreferences.getInstance();
                    if (mounted) setState(() =>
                        _vibrationEnabled = p.getBool('vibration') ?? true);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.greyDark,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.settings, color: Colors.white, size: 20),
                      SizedBox(height: 4),
                      Text('Settings', style: TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Small reusable widgets ────────────────────────────────────────────────────

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String   label, sub;
  final Color    color;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon, required this.label, required this.sub,
    required this.color, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.inputBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                color: AppColors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(color: AppColors.grey, fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.grey, size: 18),
        ]),
      ),
    );
  }
}

// ── Gesture hint row — shown on idle camera overlay ──────────────────────────
class _GestureHint extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   hint;
  const _GestureHint({required this.icon, required this.label, required this.hint});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        Icon(icon, color: AppColors.yellow, size: 14),
        const SizedBox(width: 6),
        Text('$label  ', style: const TextStyle(
            color: AppColors.yellow, fontSize: 11, fontWeight: FontWeight.w700)),
        Text(hint, style: const TextStyle(color: AppColors.grey, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Detection bounding-box painter
//  Draws:
//    • Spotlight — dark vignette outside the detected object's box
//    • Corner brackets — colour-coded by distance, pulsing when very close
//    • Subtle fill — semi-transparent tint inside the box
//    • Label tag — object name + distance above the box
//  For wall/obstacle heuristics the whole frame gets a pulsing border instead.
// ─────────────────────────────────────────────────────────────────────────────
class _DetectionBoxPainter extends CustomPainter {
  final DetectionResult result;
  final double          pulseValue;  // 0.0 – 1.0 from AnimationController

  const _DetectionBoxPainter({
    required this.result,
    required this.pulseValue,
  });

  // Distance → colour
  Color get _boxColor {
    final d = result.distanceM;
    if (d < 0.8)  return const Color(0xFFEF5350); // red   — danger
    if (d < 1.5)  return const Color(0xFFFFA726); // orange — very close
    if (d < 3.0)  return const Color(0xFFFFEB3B); // yellow — caution
    return        const Color(0xFF66BB6A);          // green  — safe
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Direct coordinate mapping ────────────────────────────────────────────
    // CameraPreview fills the entire Stack (StackFit.expand → tight constraints).
    // TFLite normalized coords [0,1] map directly to canvas pixels.
    final l = result.xMin * size.width;
    final t = result.yMin * size.height;
    final r = result.xMax * size.width;
    final b = result.yMax * size.height;

    final color     = _boxColor;
    final isClose   = result.isVeryClose;
    final isDanger  = result.distanceM < 0.8;

    // ── Wall / full-frame obstacle → pulsing border, no spotlight ────────────
    if (result.isWallHeuristic) {
      final opacity = isDanger ? 0.55 + 0.45 * pulseValue : 0.70;
      final border  = Paint()
        ..color      = color.withValues(alpha: opacity)
        ..strokeWidth = 5.0 + 3.0 * pulseValue
        ..style       = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
          const Radius.circular(14),
        ),
        border,
      );
      _drawLabel(canvas, size, 10, 10, color, size.width - 20);
      return;
    }

    // ── Spotlight — dim everything outside the bounding box ──────────────────
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawRect(Rect.fromLTRB(0,          0,          size.width, t         ), dim);
    canvas.drawRect(Rect.fromLTRB(0,          b,          size.width, size.height), dim);
    canvas.drawRect(Rect.fromLTRB(0,          t,          l,          b         ), dim);
    canvas.drawRect(Rect.fromLTRB(r,          t,          size.width, b         ), dim);

    // ── Subtle fill ───────────────────────────────────────────────────────────
    canvas.drawRect(
      Rect.fromLTRB(l, t, r, b),
      Paint()..color = color.withValues(alpha: isDanger ? 0.10 + 0.08 * pulseValue : 0.08),
    );

    // ── Corner brackets ───────────────────────────────────────────────────────
    final boxShort = (r - l) < (b - t) ? (r - l) : (b - t);
    final arm      = (boxShort * 0.22).clamp(14.0, 42.0);
    final sw       = isClose ? 3.2 + 1.8 * pulseValue : 2.8;
    final bracketColor = isClose
        ? Color.lerp(color, Colors.white, pulseValue * 0.25)!
        : color;

    final p = Paint()
      ..color      = bracketColor
      ..strokeWidth = sw
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // top-left
    canvas.drawLine(Offset(l, t + arm), Offset(l, t), p);
    canvas.drawLine(Offset(l, t),       Offset(l + arm, t), p);
    // top-right
    canvas.drawLine(Offset(r - arm, t), Offset(r, t), p);
    canvas.drawLine(Offset(r, t),       Offset(r, t + arm), p);
    // bottom-left
    canvas.drawLine(Offset(l, b - arm), Offset(l, b), p);
    canvas.drawLine(Offset(l, b),       Offset(l + arm, b), p);
    // bottom-right
    canvas.drawLine(Offset(r - arm, b), Offset(r, b), p);
    canvas.drawLine(Offset(r, b),       Offset(r, b - arm), p);

    // ── Label tag ─────────────────────────────────────────────────────────────
    _drawLabel(canvas, size, l, t, color, r - l);
  }

  void _drawLabel(Canvas canvas, Size size,
      double l, double t, Color color, double maxW) {
    final text = '${result.label}  •  ${result.distance}';
    final tp   = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color:       Colors.white,
          fontSize:    13,
          fontWeight:  FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxW.clamp(60.0, size.width - l));

    const padX = 10.0, padY = 6.0;
    final tagW   = (tp.width + padX * 2).clamp(0.0, size.width - l);
    final tagH   = tp.height + padY * 2;
    final tagTop  = (t - tagH - 5).clamp(0.0, size.height - tagH);
    final tagLeft = l.clamp(0.0, size.width - tagW);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(tagLeft, tagTop, tagW, tagH),
        const Radius.circular(6),
      ),
      Paint()..color = color,
    );
    tp.paint(canvas, Offset(tagLeft + padX, tagTop + padY));
  }

  @override
  bool shouldRepaint(_DetectionBoxPainter old) =>
      old.result     != result ||
      old.pulseValue != pulseValue;
}

// ─────────────────────────────────────────────────────────────────────────────
//  White viewfinder / focus-frame painter
//  Draws:
//    • Light vignette outside the focus zone
//    • White corner-bracket crosshairs inside the zone
//    • "FOCUS" label at top-left corner
//  The focus zone is the centre 65 % width × 62 % height of the frame.
//  Objects inside this zone are the primary announcement target.
// ─────────────────────────────────────────────────────────────────────────────
class _ViewfinderPainter extends CustomPainter {
  final bool hasDetection; // dims the viewfinder when an object box is active
  const _ViewfinderPainter({this.hasDetection = false});

  @override
  void paint(Canvas canvas, Size size) {
    // Focus zone rect — centred, 65 % wide × 62 % tall
    const hPad = 0.175; // (1 - 0.65) / 2
    const vPad = 0.190; // (1 - 0.62) / 2
    final l = size.width  * hPad;
    final t = size.height * vPad;
    final r = size.width  * (1 - hPad);
    final b = size.height * (1 - vPad);
    final rect = Rect.fromLTRB(l, t, r, b);

    // Vignette — dim outside
    if (!hasDetection) {
      final vignette = Paint()..color = Colors.black.withValues(alpha: 0.30);
      canvas.drawRect(Rect.fromLTRB(0, 0, size.width, t), vignette);
      canvas.drawRect(Rect.fromLTRB(0, b, size.width, size.height), vignette);
      canvas.drawRect(Rect.fromLTRB(0, t, l, b), vignette);
      canvas.drawRect(Rect.fromLTRB(r, t, size.width, b), vignette);
    }

    // Corner arm length — adaptive
    final armLen = (rect.shortestSide * 0.14).clamp(18.0, 44.0);

    final paint = Paint()
      ..color      = hasDetection
          ? Colors.white.withValues(alpha: 0.35) // fade when box overlay is active
          : Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = hasDetection ? 1.8 : 2.6
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    // Top-left
    canvas.drawLine(Offset(l, t + armLen), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + armLen, t), paint);
    // Top-right
    canvas.drawLine(Offset(r - armLen, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + armLen), paint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - armLen), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + armLen, b), paint);
    // Bottom-right
    canvas.drawLine(Offset(r - armLen, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - armLen), paint);

    // Small centre crosshair
    if (!hasDetection) {
      final cx = (l + r) / 2, cy = (t + b) / 2;
      const ch = 10.0;
      final cp = Paint()
        ..color      = Colors.white.withValues(alpha: 0.55)
        ..strokeWidth = 1.5
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round;
      canvas.drawLine(Offset(cx - ch, cy), Offset(cx + ch, cy), cp);
      canvas.drawLine(Offset(cx, cy - ch), Offset(cx, cy + ch), cp);
    }

    // "FOCUS" label tag — top-left corner of the frame
    if (!hasDetection) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'FOCUS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const padX = 7.0, padY = 4.0;
      final tagW = tp.width + padX * 2;
      final tagH = tp.height + padY * 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(l, t - tagH - 4, tagW, tagH),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.20),
      );
      tp.paint(canvas, Offset(l + padX, t - tagH - 4 + padY));
    }
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) =>
      old.hasDetection != hasDetection;
}
