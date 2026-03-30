import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';

class OnboardingHowItWorksScreen extends StatelessWidget {
  const OnboardingHowItWorksScreen({super.key});
  Future<void> _finish(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, AppRoutes.mainAI, (_) => false);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(),
            Container(width: 100, height: 100, decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle), child: const Icon(Icons.volume_up, color: Colors.black, size: 48)),
            const SizedBox(height: 28),
            const Text('How It Works', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.white)),
            const SizedBox(height: 12),
            const Text('Listen to learn how to use NavEye', textAlign: TextAlign.center, style: TextStyle(color: AppColors.greyLight, fontSize: 14)),
            const SizedBox(height: 40),
            _Step(number: '1', text: 'Point your phone camera forward while walking'),
            const SizedBox(height: 16),
            _Step(number: '2', text: 'NavEye detects obstacles and speaks to you'),
            const SizedBox(height: 16),
            _Step(number: '3', text: 'Say Repeat Next or Back to control'),
            const Spacer(),
            SecondaryButton(text: 'Play Instructions', icon: Icons.play_arrow, onPressed: () {}),
            const SizedBox(height: 12),
            PrimaryButton(text: 'I Understand', onPressed: () => _finish(context)),
            const SizedBox(height: 16),
            TextButton(onPressed: () => _finish(context), child: const Text('Skip', style: TextStyle(color: AppColors.grey, fontSize: 12))),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String number, text;
  const _Step({required this.number, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(8)), child: Center(child: Text(number, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700)))),
      const SizedBox(width: 14),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.white, fontSize: 14))),
    ]);
  }
}
