import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/tts_service.dart';

class PersonAddedScreen extends StatefulWidget {
  const PersonAddedScreen({super.key});
  @override
  State<PersonAddedScreen> createState() => _PersonAddedScreenState();
}

class _PersonAddedScreenState extends State<PersonAddedScreen> {
  final TtsService _tts = TtsService();
  String _name = 'Person'; // initialised with fallback; set in didChangeDependencies
  int _autoNavigateIn = 5;
  Timer? _timer;
  bool _finished = false; // BUG-C1 FIX: guard against double pop

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _name = (ModalRoute.of(context)?.settings.arguments as String?) ?? 'Person';
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), _onReady);
  }

  Future<void> _onReady() async {
    await _tts.init();
    await _tts.speakNow(
      '$_name has been saved to NavEye. '
      'NavEye will now recognise $_name when they appear in front of the camera. '
      'Returning to main screen in 5 seconds.',
    );

    // Auto-navigate countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _autoNavigateIn--);
      if (_autoNavigateIn <= 0) {
        t.cancel();
        _finish();
      }
    });
  }

  void _finish() {
    // BUG-C1 FIX: timer callback and "Done Now" button can both call _finish()
    // within the same frame. The guard ensures only the first invocation pops.
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _tts.stop();
    if (mounted) {
      // Pop back to the existing MainAIScreen (which is already alive in the
      // stack with its camera and model loaded).  Previously this called
      // pushNamedAndRemoveUntil which destroyed and recreated MainAI — causing
      // a 3–5 s camera cold-start delay every time a person was added.
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Spacer(),

            // Success icon
            Container(
              width: 120, height: 120,
              decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 70),
            ),
            const SizedBox(height: 28),

            const Text('Person Added!',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.white)),
            const SizedBox(height: 10),

            Text(
              '$_name has been saved.\nNavEye will now recognise them.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.greyLight, fontSize: 15, height: 1.5),
            ),

            const SizedBox(height: 32),

            // Auto-navigate countdown ring
            Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 64, height: 64,
                child: CircularProgressIndicator(
                  value: (_autoNavigateIn / 5).clamp(0.0, 1.0),
                  color: AppColors.yellow,
                  backgroundColor: AppColors.greyDark,
                  strokeWidth: 4,
                ),
              ),
              Text('$_autoNavigateIn',
                style: const TextStyle(color: AppColors.yellow, fontSize: 22, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            const Text('Returning to main screen...',
              style: TextStyle(color: AppColors.grey, fontSize: 12)),

            const Spacer(),

            // Manual Done button
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _finish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellow, foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Done Now', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}
