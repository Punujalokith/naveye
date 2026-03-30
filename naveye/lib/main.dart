import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme/app_theme.dart';
import 'theme/app_routes.dart';
import 'screens/onboarding/onboarding_start_screen.dart';
import 'screens/onboarding/onboarding_tell_us_screen.dart';
import 'screens/onboarding/onboarding_how_it_works_screen.dart';
import 'screens/main_ai/main_ai_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/guidelines/user_guidelines_screen.dart';
import 'screens/people/people_capture_screen.dart';
import 'screens/people/people_enter_name_screen.dart';
import 'screens/people/person_added_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final bool onboardingDone = prefs.getBool('onboarding_complete') ?? false;
  runApp(NavEyeApp(onboardingDone: onboardingDone));
}

class NavEyeApp extends StatelessWidget {
  final bool onboardingDone;
  const NavEyeApp({super.key, required this.onboardingDone});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NavEye',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: onboardingDone ? AppRoutes.mainAI : AppRoutes.onboardingStart,
      routes: {
        AppRoutes.onboardingStart: (_) => const OnboardingStartScreen(),
        AppRoutes.onboardingTellUs: (_) => const OnboardingTellUsScreen(),
        AppRoutes.onboardingHowItWorks: (_) => const OnboardingHowItWorksScreen(),
        AppRoutes.mainAI: (_) => const MainAIScreen(),
        AppRoutes.settings: (_) => const SettingsScreen(),
        AppRoutes.guidelines: (_) => const UserGuidelinesScreen(),
        AppRoutes.peopleCapture: (_) => const PeopleCaptureScreen(),
        AppRoutes.peopleEnterName: (_) => const PeopleEnterNameScreen(),
        AppRoutes.personAdded: (_) => const PersonAddedScreen(),
      },
    );
  }
}
