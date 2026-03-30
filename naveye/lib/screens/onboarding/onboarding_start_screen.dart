import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';

class OnboardingStartScreen extends StatelessWidget {
  const OnboardingStartScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(flex: 2),
            Align(alignment: Alignment.topRight, child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle))),
            const Spacer(),
            const NavEyeLogo(),
            const Spacer(flex: 3),
            PrimaryButton(text: 'Start Now', onPressed: () => Navigator.pushNamed(context, AppRoutes.onboardingTellUs)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.mic_none, color: AppColors.grey, size: 14),
              SizedBox(width: 6),
              Text('Voice guidance enable', style: TextStyle(color: AppColors.grey, fontSize: 12)),
            ]),
            const Spacer(flex: 2),
          ]),
        ),
      ),
    );
  }
}
