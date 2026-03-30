import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';

class MainAIScreen extends StatefulWidget {
  const MainAIScreen({super.key});
  @override
  State<MainAIScreen> createState() => _MainAIScreenState();
}
class _MainAIScreenState extends State<MainAIScreen> {
  bool _isDetecting = false;
  void _toggle() => setState(() => _isDetecting = !_isDetecting);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16,12,16,0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.search, color: AppColors.grey, size: 18), const SizedBox(width: 8),
              Expanded(child: Text(_isDetecting ? 'Detecting obstacles...' : 'Tap to start detection', style: const TextStyle(color: AppColors.greyLight, fontSize: 13))),
              if (_isDetecting) Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)),
            ]),
          ),
        ),
        Expanded(child: Padding(
          padding: const EdgeInsets.all(16),
          child: GestureDetector(
            onTap: _toggle,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _isDetecting ? AppColors.green : AppColors.greyDark, width: _isDetecting ? 2 : 1)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 72, height: 72, decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(36)), child: Icon(_isDetecting ? Icons.camera_alt : Icons.camera_alt_outlined, color: _isDetecting ? AppColors.green : AppColors.grey, size: 36)),
                const SizedBox(height: 16),
                Text(_isDetecting ? 'Scanning...' : 'Tap to Start Detection', style: TextStyle(color: _isDetecting ? AppColors.green : AppColors.greyLight, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Camera live feed will appear here', style: TextStyle(color: AppColors.grey, fontSize: 12)),
              ]),
            ),
          ),
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16,0,16,16),
          child: Row(children: [
            Expanded(child: GestureDetector(onTap: () => Navigator.pushNamed(context, AppRoutes.peopleCapture), child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(12)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.people, color: Colors.black, size: 18), SizedBox(width: 8), Text('People', style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w600))])))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(onTap: () => Navigator.pushNamed(context, AppRoutes.settings), child: Container(padding: const EdgeInsets.symmetric(vertical: 14), decoration: BoxDecoration(color: AppColors.greyDark, borderRadius: BorderRadius.circular(12)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.settings, color: Colors.white, size: 18), SizedBox(width: 8), Text('Settings', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600))])))),
          ]),
        ),
      ])),
    );
  }
}
