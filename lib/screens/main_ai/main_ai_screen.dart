import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';

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
  String _statusText = 'Tap to start detection';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
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
      debugPrint('Camera error: \');
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
    _cameraController?.dispose();
    super.dispose();
  }

  void _toggleDetection() {
    if (!_cameraReady) return;
    setState(() {
      _isDetecting = !_isDetecting;
      _statusText = _isDetecting ? 'Detecting obstacles...' : 'Tap to start detection';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Column(children: [
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
        Expanded(child: Padding(
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
                  border: Border.all(color: _isDetecting ? AppColors.green : AppColors.greyDark, width: _isDetecting ? 2 : 1),
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
                            ]),
                          ),
                        if (_isDetecting)
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
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                        CircularProgressIndicator(color: AppColors.yellow, strokeWidth: 2),
                        SizedBox(height: 16),
                        Text('Initializing camera...', style: TextStyle(color: AppColors.greyLight, fontSize: 14)),
                      ]),
              ),
            ),
          ),
        )),
        if (_isDetecting)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: const [
              _DirectionChip(label: 'LEFT', active: false),
              _DirectionChip(label: 'CENTER', active: true),
              _DirectionChip(label: 'RIGHT', active: false),
            ]),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.peopleCapture),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people, color: Colors.black, size: 18), SizedBox(width: 8), Text('People', style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600))])),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRoutes.settings),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(12)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.settings, color: Colors.white, size: 18), SizedBox(width: 8), Text('Settings', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))])),
            )),
          ]),
        ),
      ])),
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
      child: Text(label, style: TextStyle(color: active ? AppColors.green : AppColors.grey, fontSize: 12, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
    );
  }
}
