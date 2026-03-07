import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../services/shared_stt.dart';
import '../services/tts_service.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Buttons
// ─────────────────────────────────────────────────────────────────────────────

class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  const PrimaryButton({super.key, required this.text, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellow,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final IconData? icon;
  const SecondaryButton({super.key, required this.text, required this.onPressed, this.icon});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Logo
// ─────────────────────────────────────────────────────────────────────────────

class NavEyeLogo extends StatelessWidget {
  const NavEyeLogo({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: 70, height: 70,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.greyDark),
        ),
        child: const Icon(Icons.remove_red_eye_outlined, color: AppColors.yellow, size: 36),
      ),
      const SizedBox(height: 12),
      const Text('NavEye',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.white)),
      const Text('Your Assistant',
          style: TextStyle(fontSize: 13, color: AppColors.grey)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  VoiceTextField — text field + mic button using shared STT singleton
// ─────────────────────────────────────────────────────────────────────────────

class VoiceTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;

  const VoiceTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<VoiceTextField> createState() => _VoiceTextFieldState();
}

class _VoiceTextFieldState extends State<VoiceTextField> {
  bool  _listening    = false;
  // BUG-9 FIX: use nullable bool so we can distinguish three states:
  //   null  = STT initialising (show spinner, taps silently ignored)
  //   false = STT unavailable  (show disabled grey mic)
  //   true  = STT ready        (show yellow tappable mic)
  bool? _sttAvailable;

  @override
  void initState() {
    super.initState();
    SharedStt.instance.init().then((ok) {
      debugPrint('VoiceTextField(${widget.label}): STT available=$ok');
      if (mounted) setState(() => _sttAvailable = ok);
    });
  }

  @override
  void dispose() {
    if (_listening) SharedStt.instance.stop();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (_sttAvailable != true || _listening) return;

    // FIX-1: Stop TTS before starting STT. If TTS is still speaking the
    // opening guidance, STT gets error_audio immediately (both compete for
    // the audio focus / microphone on Android).
    await TtsService().stop();

    if (SharedStt.instance.isListening) {
      await SharedStt.instance.stop();
    }
    // Samsung audio hardware needs ~500 ms to fully release after TTS/previous
    // STT session before a new listen() call can succeed without error_busy.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() => _listening = true);

    // Reset mic on any STT error (error_audio, error_busy, network, etc.)
    SharedStt.instance.setErrorListener((e) {
      debugPrint('STT error in VoiceTextField: ${e.errorMsg}');
      SharedStt.instance.clearListeners();
      if (mounted) setState(() => _listening = false);
    });

    // FIX-3: Status listener — reset mic when STT engine reports done/stopped.
    // Without this, if STT ends without a finalResult (e.g. silence timeout),
    // the mic button stays green/ON forever.
    SharedStt.instance.setStatusListener((status) {
      debugPrint('STT status in VoiceTextField: $status');
      if (status == 'notListening' || status == 'done') {
        SharedStt.instance.clearListeners();
        if (mounted) setState(() => _listening = false);
      }
    });

    try {
      debugPrint('STT listen ← VoiceTextField (label="${widget.label}")');
      await SharedStt.instance.raw.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) widget.controller?.text = words;
          if (result.finalResult) {
            SharedStt.instance.clearListeners();
            if (mounted) setState(() => _listening = false);
          }
        },
        listenFor: const Duration(seconds: 15),
        pauseFor:  const Duration(seconds: 5),
        // FIX-2: onDevice: true fails on devices without an on-device speech
        // model (e.g. Samsung A30 Android 10 with no offline model installed).
        // Using cloud-based recognition (onDevice: false) is reliable on all
        // Android devices that have Google app installed.
        listenOptions: SpeechListenOptions(
          cancelOnError:  false,
          partialResults: true,
          onDevice:       false,
        ),
      );
      // NOTE: raw.listen() returns as soon as the session STARTS (it is NOT
      // a blocking call that waits for final result). Do NOT reset _listening
      // here — the status listener and onResult handle that asynchronously.
    } catch (e) {
      debugPrint('STT listen exception: $e');
      SharedStt.instance.clearListeners();
      if (mounted) setState(() => _listening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(widget.label,
          style: const TextStyle(
              color: AppColors.greyLight, fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextField(
            controller: widget.controller,
            keyboardType: widget.keyboardType,
            style: const TextStyle(color: AppColors.white, fontSize: 14),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _listening
              ? () async {
                  SharedStt.instance.clearListeners();
                  await SharedStt.instance.stop();
                  if (mounted) setState(() => _listening = false);
                }
              : (_sttAvailable == true ? _startListening : null),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46, height: 46,
            decoration: BoxDecoration(
              // ON      = green fill + glow (clearly active)
              // OFF     = dark fill + yellow border (clearly tappable)
              // LOADING = dark fill + grey border (init in progress)
              color: _listening ? AppColors.green : AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: _listening
                    ? AppColors.green
                    : _sttAvailable == true
                        ? AppColors.yellow
                        : AppColors.greyDark,
                width: _listening ? 2.0 : 1.5,
              ),
              boxShadow: _listening
                  ? [BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.4),
                      blurRadius: 10, spreadRadius: 1)]
                  : null,
            ),
            child: _sttAvailable == null
                // Initialising — show tiny spinner
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                        strokeWidth: 1.5, color: AppColors.grey))
                : Icon(
                    _listening ? Icons.mic : Icons.mic_none,
                    // ON = white;  OFF ready = yellow;  unavailable = grey
                    color: _listening
                        ? Colors.white
                        : _sttAvailable == true
                            ? AppColors.yellow
                            : AppColors.grey,
                    size: 22,
                  ),
          ),
        ),
      ]),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LabelledTextField  (kept for backward compat)
// ─────────────────────────────────────────────────────────────────────────────

class LabelledTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final TextInputType keyboardType;
  const LabelledTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.keyboardType = TextInputType.text,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              color: AppColors.greyLight, fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: AppColors.white, fontSize: 14),
        decoration: InputDecoration(hintText: hint),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LevelSelector
// ─────────────────────────────────────────────────────────────────────────────

class LevelSelector extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;
  const LevelSelector({
    super.key,
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: AppColors.greyLight, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: AppColors.white, fontSize: 14)),
      ]),
      const SizedBox(height: 10),
      Row(children: options.map((opt) {
        final sel = opt == selected;
        return Expanded(child: GestureDetector(
          onTap: () => onSelected(opt),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppColors.yellow : AppColors.inputBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(opt, style: TextStyle(
              color: sel ? Colors.black : AppColors.greyLight,
              fontSize: 13,
              fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
            ))),
          ),
        ));
      }).toList()),
    ]);
  }
}
