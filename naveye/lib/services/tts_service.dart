import 'dart:async';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Text-to-Speech service — always English (en-US).
///
/// BUG-8 FIX: Converted to a singleton via Dart factory constructor.
/// Previously every screen created `final TtsService _tts = TtsService()`,
/// each creating a separate FlutterTts engine.  Multiple engines compete on
/// the single Android TTS channel — calling stop() on one does NOT stop
/// another engine's speech, causing overlapping / echoing audio.
/// The factory constructor means `TtsService()` always returns the same instance.
class TtsService {
  // ── Singleton ─────────────────────────────────────────────────────────────
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;
  TtsService._internal();

  final FlutterTts _tts = FlutterTts();
  bool   _isSpeaking = false;
  bool   _muted      = false;
  String _lastSpoken = '';

  // BUG-6 FIX: use Timer so it can be cancelled when dispose() is called.
  // Previously Future.delayed continued running after the screen was disposed.
  Timer? _speakTimer;

  bool get isSpeaking => _isSpeaking;
  void mute()   => _muted = true;
  void unmute() => _muted = false;

  /// Register a one-shot callback fired when the current speech finishes.
  void setOnComplete(VoidCallback cb) {
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      cb();
    });
  }

  Future<void> init() async {
    final prefs  = await SharedPreferences.getInstance();
    final volume = prefs.getString('voice_volume') ?? 'Medium';

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(volume == 'High' ? 1.0 : volume == 'Low' ? 0.35 : 0.8);
    await _tts.setPitch(1.0);

    // Restore default handlers (setOnComplete may have overridden completion)
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setErrorHandler((_)    => _isSpeaking = false);
    _tts.setCancelHandler(()    => _isSpeaking = false);
  }

  /// Obstacle announcement — skipped if muted or duplicate.
  Future<void> announce(String text) async {
    if (_muted) return;
    if (_isSpeaking && text == _lastSpoken) return;
    _lastSpoken = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
    _armTimeout();
  }

  /// General speech — respects mute + deduplication.
  Future<void> speak(String text) async {
    // BUG-7 FIX: speak() now respects mute (previously only announce() did).
    if (_muted) return;
    if (_isSpeaking && text == _lastSpoken) return;
    _lastSpoken = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
    _armTimeout();
  }

  /// Always speaks immediately — interrupts current speech, ignores mute.
  Future<void> speakNow(String text) async {
    _lastSpoken = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
    _armTimeout();
  }

  void _armTimeout() {
    _speakTimer?.cancel();
    _speakTimer = Timer(
      const Duration(seconds: 25),
      () => _isSpeaking = false,
    );
  }

  Future<void> stop() async {
    _speakTimer?.cancel();
    await _tts.stop();
    _isSpeaking = false;
  }

  /// No-op in singleton context — the engine is kept alive for the app lifetime.
  /// Calling stop() is still safe and will halt current speech.
  void dispose() {
    _speakTimer?.cancel();
    _tts.stop();
  }
}
