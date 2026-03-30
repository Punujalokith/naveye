import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';

class PeopleCaptureScreen extends StatelessWidget {
  const PeopleCaptureScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_ios, size:18), onPressed: () => Navigator.pop(context)), title: const Text('People Capture')),
      body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
        const Spacer(),
        Container(width:140, height:140, decoration: BoxDecoration(color: AppColors.surface, shape: BoxShape.circle, border: Border.all(color: AppColors.greyDark, width:2)), child: const Icon(Icons.person, color: AppColors.grey, size:72)),
        const SizedBox(height:24),
        const Text('Position Person Face', style: TextStyle(color: AppColors.greyLight, fontSize:15)),
        const SizedBox(height:8),
        const Text('Centre the face in frame then tap Capture', textAlign: TextAlign.center, style: TextStyle(color: AppColors.grey, fontSize:13)),
        const Spacer(),
        SizedBox(width: double.infinity, height:52, child: ElevatedButton.icon(onPressed: () => Navigator.pushNamed(context, AppRoutes.peopleEnterName), icon: const Icon(Icons.camera_alt, size:20), label: const Text('Capture', style: TextStyle(fontSize:16, fontWeight: FontWeight.w700)), style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
        const SizedBox(height:20),
      ])),
    );
  }
}
