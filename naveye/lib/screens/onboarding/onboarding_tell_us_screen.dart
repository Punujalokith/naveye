import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../services/tts_service.dart';

class OnboardingTellUsScreen extends StatefulWidget {
  const OnboardingTellUsScreen({super.key});
  @override
  State<OnboardingTellUsScreen> createState() => _OnboardingTellUsScreenState();
}

class _OnboardingTellUsScreenState extends State<OnboardingTellUsScreen> {
  final _nameCtrl      = TextEditingController();
  final _ageCtrl       = TextEditingController();
  final _phoneCtrl     = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _tts           = TtsService();

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _tts.init();
      await _tts.speakNow(
        'Tell us about you. '
        'Please enter your name using the mic button next to each field. '
        'Tap the yellow microphone and speak clearly. '
        'Only your name is required. All other fields are optional.',
      );
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _phoneCtrl.dispose();
    _emergencyCtrl.dispose();
    _tts.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_nameCtrl.text.trim().isEmpty) {
      await _tts.speakNow('Please enter your name first.');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter your name'),
            backgroundColor: AppColors.danger));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name',      _nameCtrl.text.trim());
    await prefs.setString('user_age',       _ageCtrl.text.trim());
    await prefs.setString('user_phone',     _phoneCtrl.text.trim());
    await prefs.setString('user_emergency', _emergencyCtrl.text.trim());
    if (!mounted) return;
    Navigator.pushNamed(context, AppRoutes.onboardingHowItWorks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Header ────────────────────────────────────────────────────────
            const Center(
              child: Text('Tell Us About You',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white)),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Tap the yellow mic button and speak to fill each field',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.grey, fontSize: 13),
              ),
            ),
            const SizedBox(height: 32),

            // ── Name (required) ───────────────────────────────────────────────
            _sectionLabel('Your Name', required: true),
            const SizedBox(height: 6),
            VoiceTextField(
              label: '',
              hint: 'Speak or type your name',
              controller: _nameCtrl,
            ),
            const SizedBox(height: 20),

            // ── Age ───────────────────────────────────────────────────────────
            _sectionLabel('Age', required: false),
            const SizedBox(height: 6),
            VoiceTextField(
              label: '',
              hint: 'e.g. 28  (optional)',
              controller: _ageCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),

            // ── Phone ─────────────────────────────────────────────────────────
            _sectionLabel('Your Phone Number', required: false),
            const SizedBox(height: 6),
            VoiceTextField(
              label: '',
              hint: 'Your phone number  (optional)',
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),

            // ── Emergency Contact ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.emergency_outlined, color: AppColors.danger, size: 15),
                  SizedBox(width: 6),
                  Text('Emergency Contact  (optional)',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 4),
                const Text(
                  'Caretaker name or phone number',
                  style: TextStyle(color: AppColors.grey, fontSize: 11),
                ),
                const SizedBox(height: 10),
                VoiceTextField(
                  label: '',
                  hint: 'Speak or type emergency contact',
                  controller: _emergencyCtrl,
                  keyboardType: TextInputType.phone,
                ),
              ]),
            ),

            const SizedBox(height: 40),
            PrimaryButton(text: 'Continue', onPressed: _continue),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.onboardingHowItWorks),
                child: const Text('Skip for now',
                    style: TextStyle(color: AppColors.grey, fontSize: 13)),
              ),
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, {required bool required}) {
    return Row(children: [
      Text(text,
          style: const TextStyle(
              color: AppColors.greyLight,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
      if (required) ...[
        const SizedBox(width: 4),
        const Text('*', style: TextStyle(color: AppColors.danger, fontSize: 13)),
      ],
    ]);
  }
}
