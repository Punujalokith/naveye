import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/nav_eye_foreground_service.dart';
import 'theme/app_theme.dart';
import 'theme/app_routes.dart';
import 'screens/auth/user_profile_screen.dart';
import 'screens/onboarding/onboarding_start_screen.dart';
import 'screens/onboarding/onboarding_tell_us_screen.dart';
import 'screens/onboarding/onboarding_how_it_works_screen.dart';
import 'screens/main_ai/main_ai_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/guidelines/user_guidelines_screen.dart';
import 'screens/people/people_capture_screen.dart';
import 'screens/people/people_enter_name_screen.dart';
import 'screens/people/person_added_screen.dart';
import 'screens/people/people_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Initialise foreground service configuration before the app starts.
  // The actual service is only STARTED when detection begins — this
  // call just registers the notification channel and task options.
  NavEyeForegroundService.init();

  final prefs = await SharedPreferences.getInstance();
  final bool onboardingDone = prefs.getBool('onboarding_complete') ?? false;
  runApp(
    WithForegroundTask(child: NavEyeApp(onboardingDone: onboardingDone)),
  );
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
        AppRoutes.onboardingStart:    (_) => const OnboardingStartScreen(),
        AppRoutes.onboardingTellUs:   (_) => const OnboardingTellUsScreen(),
        AppRoutes.onboardingHowItWorks: (_) => const OnboardingHowItWorksScreen(),
        // BUG-33 FIX: read optional bool argument so SettingsScreen can open
        // the profile in edit mode via pushNamed(..., arguments: true).
        AppRoutes.userProfile: (ctx) {
          final isEdit = ModalRoute.of(ctx)!.settings.arguments as bool? ?? false;
          return UserProfileScreen(isEdit: isEdit);
        },
        AppRoutes.mainAI:             (_) => const MainAIScreen(),
        AppRoutes.settings:           (_) => const SettingsScreen(),
        AppRoutes.guidelines:         (_) => const UserGuidelinesScreen(),
        AppRoutes.peopleCapture:      (_) => const PeopleCaptureScreen(),
        AppRoutes.peopleEnterName:    (_) => const PeopleEnterNameScreen(),
        AppRoutes.personAdded:        (_) => const PersonAddedScreen(),
        AppRoutes.peopleList:         (_) => const PeopleListScreen(),
      },
    );
  }
}
