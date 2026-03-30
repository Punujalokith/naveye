import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';

class PersonAddedScreen extends StatelessWidget {
  const PersonAddedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final name = (ModalRoute.of(context)?.settings.arguments as String?) ?? 'Person';
    return Scaffold(
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Spacer(),
        Container(width:110, height:110, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size:60)),
        const SizedBox(height:28),
        const Text('Person Added!', style: TextStyle(fontSize:24, fontWeight: FontWeight.w700, color: AppColors.white)),
        const SizedBox(height:10),
        Text('\ has been saved', style: const TextStyle(color: AppColors.greyLight, fontSize:15)),
        const Spacer(),
        SizedBox(width: double.infinity, height:52, child: ElevatedButton(onPressed: () => Navigator.pushNamedAndRemoveUntil(context, AppRoutes.mainAI, (_) => false), style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Done', style: TextStyle(fontSize:16, fontWeight: FontWeight.w700)))),
        const SizedBox(height:20),
      ]))),
    );
  }
}
