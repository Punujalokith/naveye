import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../services/detector_service.dart';
import '../../services/tts_service.dart';

class MainAIScreen extends StatefulWidget {
  const MainAIScreen({super.key});
  @override
  State<MainAIScreen> createState() => _MainAIScreenState();
}

class _MainAIScreenState extends State<MainAIScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isDetecting = false;
  bool _cameraReady = false;
  bool _modelReady = false;
  String _statusText = 'Initializing...';
  String _detectionLabel = '';
  String _direction = 'CENTER';
  String _distance = '';
  final DetectorService _detector = DetectorService();
  final TtsService _tts = TtsService();
  DateTime _lastDetection = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _tts.init();
    await _detector.loadModel();
    setState(() {
      _modelReady = _detector.isLoaded;
      _statusText = _modelReady ? 'Tap to start detection' : 'Model load failed';
    });
    await _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      _cameraController = CameraController(
        _cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _toggleDetection() {
    if (!_cameraReady || !_modelReady) return;
    setState(() {
      _isDetecting = !_isDetecting;
      _statusText = _isDetecting ? 'Detecting obstacles...' : 'Tap to start detection';
      _detectionLabel = '';
    });
    if (_isDetecting) {
      _startImageStream();
    } else {
      _cameraController?.stopImageStream();
      _tts.stop();
    }
  }

  void _startImageStream() {
    _cameraController?.startImageStream((CameraImage cameraImage) async {
      final now = DateTime.now();
      if (now.difference(_lastDetection).inMilliseconds < 800) return;
      _lastDetection = now;
      try {
        final image = _convertCameraImage(cameraImage);
        if (image == null) return;
        final results = await _detector.detect(image);
        if (results.isEmpty) {
          if (mounted) setState(() {
            _detectionLabel = 'No obstacles detected';
            _direction = 'CENTER';
            _distance = '';
          });
          return;
        }
        final top = results.first;
        if (mounted) setState(() {
          _detectionLabel = top.label;
          _direction = top.direction.toUpperCase();
          _distance = top.distance;
        });
        await _tts.speak(top.announcement);
      } catch (e) {
        debugPrint('Detection error: $e');
      }
    });
  }

  img.Image? _convertCameraImage(CameraImage cameraImage) {
    try {
      final width = cameraImage.width;
      final height = cameraImage.height;
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];
      final image = img.Image(width: width, height: height);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final yVal = yPlane.bytes[y * yPlane.bytesPerRow + x];
          final uvIndex = (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uPlane.bytesPerPixel!;
          final uVal = uPlane.bytes[uvIndex];
          final vVal = vPlane.bytes[uvIndex];
          final r = (yVal + 1.370705 * (vVal - 128)).clamp(0, 255).toInt();
          final g = (yVal - 0.337633 * (uVal - 128) - 0.698001 * (vVal - 128)).clamp(0, 255).toInt();
          final b = (yVal + 1.732446 * (uVal - 128)).clamp(0, 255).toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return image;
    } catch (e) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _detector.dispose();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.search, color: AppColors.grey, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_statusText, style: const TextStyle(color: AppColors.greyLight, fontSize: 13))),
                  if (_isDetecting) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
                ]),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: _toggleDetection,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _isDetecting ? AppColors.green : AppColors.greyDark,
                          width: _isDetecting ? 2 : 1,
                        ),
                      ),
                      child: _cameraReady
                          ? Stack(fit: StackFit.expand, children: [
                              CameraPreview(_cameraController!),
                              if (!_isDetecting)
                                Container(
                                  color: Colors.black54,
                                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                                    Icon(Icons.touch_app, color: AppColors.yellow, size: 48),
                                    SizedBox(height: 12),
                                    Text('Tap to Start Detection', style: TextStyle(color: AppColors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                    SizedBox(height: 8),
                                    Text('AI model ready', style: TextStyle(color: AppColors.green, fontSize: 12)),
                                  ]),
                                ),
                              if (_isDetecting) ...[
                                Positioned(
                                  top: 12, left: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(color: AppColors.green, borderRadius: BorderRadius.circular(20)),
                                    child: const Row(children: [
                                      Icon(Icons.fiber_manual_record, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                    ]),
                                  ),
                                ),
                                if (_detectionLabel.isNotEmpty)
                                  Positioned(
                                    bottom: 12, left: 12, right: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(_detectionLabel, style: const TextStyle(color: AppColors.yellow, fontSize: 16, fontWeight: FontWeight.w700)),
                                        if (_distance.isNotEmpty)
                                          Text(_distance, style: const TextStyle(color: AppColors.white, fontSize: 12)),
                                      ]),
                                    ),
                                  ),
                              ],
                            ])
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                              CircularProgressIndicator(color: AppColors.yellow, strokeWidth: 2),
                              SizedBox(height: 16),
                              Text('Initializing camera...', style: TextStyle(color: AppColors.greyLight, fontSize: 14)),
                            ]),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _DirectionChip(label: 'LEFT', active: _direction == 'LEFT'),
                  _DirectionChip(label: 'CENTER', active: _direction == 'CENTER'),
                  _DirectionChip(label: 'RIGHT', active: _direction == 'RIGHT'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.peopleCapture),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.people, color: Colors.black, size: 18),
                        SizedBox(width: 8),
                        Text('People', style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(12)),
                      child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.settings, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Settings', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionChip extends StatelessWidget {
  final String label;
  final bool active;
  const _DirectionChip({required this.label, required this.active});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: active ? AppColors.green.withOpacity(0.2) : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? AppColors.green : AppColors.greyDark),
      ),
      child: Text(label, style: TextStyle(
        color: active ? AppColors.green : AppColors.grey,
        fontSize: 12,
        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
      )),
    );
  }
}
