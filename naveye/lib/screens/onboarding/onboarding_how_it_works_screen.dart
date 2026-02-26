import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../../services/tts_service.dart';

class OnboardingHowItWorksScreen extends StatefulWidget {
  const OnboardingHowItWorksScreen({super.key});
  @override
  State<OnboardingHowItWorksScreen> createState() => _OnboardingHowItWorksScreenState();
}

class _OnboardingHowItWorksScreenState extends State<OnboardingHowItWorksScreen> {
  final TtsService _tts = TtsService();
  bool _playing = false;

  static const String _instructions =
      'Welcome to NavEye, your AI blind assistance app. '
      'Here is how to use it. '
      'Step 1. Point your phone camera forward while walking. '
      'Step 2. NavEye detects obstacles and speaks their name, direction, and distance to you. '
      'Step 3. Say Start to begin detection. Say Stop to stop. Say Repeat to hear the last detection again. '
      'Say Who is this to identify a person in front of you. '
      'To add a person, tap the People button and take their photo. '
      'You are ready to use NavEye. Tap I Understand to continue.';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _tts.init();
    // Auto-play instructions after a short delay so the screen renders first
    Future.delayed(const Duration(milliseconds: 600), _playInstructions);
  }

  Future<void> _playInstructions() async {
    if (!mounted) return;
    setState(() => _playing = true);
    // Wire up completion before speaking so _playing resets as soon as TTS ends.
    // The old word-count delay was ~100 s which far exceeded the actual speech
    // duration (~40 s at rate 0.45), leaving "Playing..." showing indefinitely.
    _tts.setOnComplete(() { if (mounted) setState(() => _playing = false); });
    await _tts.speakNow(_instructions);
  }

  Future<void> _finish(BuildContext context) async {
    await _tts.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, AppRoutes.mainAI, (_) => false);
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(children: [
            const Spacer(),
            Container(
              width: 100, height: 100,
              decoration: const BoxDecoration(color: AppColors.yellow, shape: BoxShape.circle),
              child: Icon(
                _playing ? Icons.volume_up : Icons.volume_up_outlined,
                color: Colors.black, size: 48,
              ),
            ),
            const SizedBox(height: 28),
            const Text('How It Works',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.white)),
            const SizedBox(height: 12),
            Text(
              _playing ? 'Playing instructions...' : 'Listen to learn how to use NavEye',
              textAlign: TextAlign.center,
              style: TextStyle(color: _playing ? AppColors.green : AppColors.greyLight, fontSize: 14),
            ),
            const SizedBox(height: 40),
            const _Step(number: '1', text: 'Point your phone camera forward while walking'),
            const SizedBox(height: 16),
            const _Step(number: '2', text: 'NavEye detects obstacles and speaks name, direction & distance'),
            const SizedBox(height: 16),
            const _Step(number: '3', text: 'Say "Start", "Stop", "Repeat", or "Who is this" to control'),
            const Spacer(),
            SecondaryButton(
              text: _playing ? 'Playing...' : 'Play Instructions',
              icon: _playing ? Icons.pause : Icons.play_arrow,
              onPressed: _playing ? () async { await _tts.stop(); setState(() => _playing = false); } : _playInstructions,
            ),
            const SizedBox(height: 12),
            PrimaryButton(text: 'I Understand', onPressed: () => _finish(context)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => _finish(context),
              child: const Text('Skip', style: TextStyle(color: AppColors.grey, fontSize: 12)),
            ),
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
      Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(8)),
        child: Center(child: Text(number, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700))),
      ),
      const SizedBox(width: 14),
      Expanded(child: Text(text, style: const TextStyle(color: AppColors.white, fontSize: 14))),
    ]);
  }
}
