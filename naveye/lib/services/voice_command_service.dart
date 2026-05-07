import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'shared_stt.dart';

enum VoiceCommand {
  start, stop, repeat, whoIsThis, openSettings, openPeople, help, unknown
}

class VoiceCommandService {
  bool _listening = false;
  bool get isListening => _listening;

  /// Lazy-init: call this to warm up STT when convenient (e.g. after the first
  /// tap). Intentionally avoided at app start on Samsung devices because calling
  /// initialize() triggers Samsung's speech service warm-up (200 ms STT cycles).
  Future<bool> init() => SharedStt.instance.init();

  Future<void> startListening(void Function(VoiceCommand) onCommand) async {
    // Lazy-init — only initialise STT the first time the user triggers voice.
    // This avoids Samsung's automatic speech-service warm-up at startup.
    final available = await SharedStt.instance.init();
    if (!available) {
      debugPrint('VoiceCmd: STT not available after lazy init');
      onCommand(VoiceCommand.unknown);
      return;
    }

    // Stop anything currently listening
    if (SharedStt.instance.isListening) {
      await SharedStt.instance.stop();
      await Future.delayed(const Duration(milliseconds: 300));
    }

    _listening = true;
    // Samsung Galaxy A30 (Android 10): on-device STT model is often missing or
    // blocked by Bixby → silent fail within 200 ms.
    // Cloud STT is significantly more reliable on Samsung; use it as PRIMARY.
    // onDevice=false still works offline on some Samsungs but falls back
    // gracefully when no network — the error handler retries with onDevice=true.
    await _doListen(onCommand, retryLeft: 2, onDevice: false);
  }

  Future<void> _doListen(
    void Function(VoiceCommand) onCommand, {
    required int retryLeft,
    bool onDevice = true,
  }) async {
    bool done = false;

    void finish(String words) async {
      if (done) return;
      done = true;
      _listening = false;
      SharedStt.instance.clearListeners();
      await SharedStt.instance.stop();
      debugPrint('VoiceCmd recognised: "$words"');
      onCommand(_parse(words));
    }

    void abort() {
      if (done) return;
      done = true;
      _listening = false;
      SharedStt.instance.clearListeners();
      onCommand(VoiceCommand.unknown);
    }

    // FIX-2: Status listener — catches silent STT stops (e.g. the engine
    // transitions to "notListening" after pauseFor timeout without firing a
    // finalResult). Without this the 12-second _voiceTimeout is the only
    // recovery, leaving the user waiting with no feedback.
    SharedStt.instance.setStatusListener((String status) {
      debugPrint('VoiceCmd status: $status  done=$done');
      if ((status == 'notListening' || status == 'done') && !done) {
        // STT ended without a result — treat as no command heard.
        // Small delay so any in-flight onResult callback fires first.
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!done) abort();
        });
      }
    });

    // Register error listener — fires when network/audio error occurs mid-listen
    SharedStt.instance.setErrorListener((SpeechRecognitionError error) async {
      if (done) return;
      final msg = error.errorMsg;
      debugPrint('VoiceCmd error: $msg  retryLeft=$retryLeft  onDevice=$onDevice');

      // error_busy           = mic in use → abort, don't fight it
      // error_speech_timeout = user didn't speak → abort gracefully
      // error_no_match       = no speech detected → abort gracefully
      // error_network        = transient connectivity → retry
      // error_language_not_supported / error_client = on-device model missing
      //   → fall back to cloud STT (onDevice=false)
      final isNetworkRetry   = msg.contains('error_network') && retryLeft > 0;
      final isOnDeviceFailed = onDevice &&
          (msg.contains('error_language_not_supported') ||
           msg.contains('error_client') ||
           msg.contains('error_not_supported'));

      if (isNetworkRetry) {
        done = true;
        SharedStt.instance.clearListeners();
        try { await SharedStt.instance.stop(); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 800));
        if (_listening) {
          debugPrint('VoiceCmd retrying network… ($retryLeft left)');
          await _doListen(onCommand, retryLeft: retryLeft - 1, onDevice: onDevice);
        }
      } else if (isOnDeviceFailed) {
        // On-device model unavailable — retry with cloud STT.
        // Use retryLeft - 1 so the total attempts across both modes is bounded.
        done = true;
        SharedStt.instance.clearListeners();
        try { await SharedStt.instance.stop(); } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
        if (_listening && retryLeft > 0) {
          debugPrint('VoiceCmd: on-device unavailable, switching to cloud STT (retryLeft=${retryLeft - 1})');
          await _doListen(onCommand, retryLeft: retryLeft - 1, onDevice: false);
        } else if (_listening) {
          debugPrint('VoiceCmd: on-device unavailable, no retries left — aborting');
          abort();
        }
      } else {
        // All other errors: stop cleanly and return unknown command
        abort();
      }
    });

    try {
      debugPrint('STT listen ← VoiceCommandService (onDevice=$onDevice retryLeft=$retryLeft)');
      await SharedStt.instance.raw.listen(
        onResult: (result) {
          final words = result.recognizedWords.toLowerCase().trim();
          if (words.isEmpty) return;
          if (result.finalResult) {
            finish(words);
            return;
          }
          // Fire immediately on partial if command is already clear
          final cmd = _parse(words);
          if (cmd != VoiceCommand.unknown) finish(words);
        },
        listenFor: const Duration(seconds: 10), // was 15 — faster timeout
        pauseFor:  const Duration(seconds: 2),  // was 5 — responds quicker after speech ends
        listenOptions: SpeechListenOptions(
          cancelOnError:  false,
          partialResults: true,
          onDevice:       onDevice,
        ),
      );
    } catch (e) {
      debugPrint('VoiceCmd listen error: $e');
      abort();
    }
  }

  Future<void> stopListening() async {
    _listening = false;
    SharedStt.instance.clearListeners();
    await SharedStt.instance.stop();
  }

  VoiceCommand _parse(String words) {
    if (words.isEmpty) { return VoiceCommand.unknown; }
    if (_has(words, ['start', 'begin', 'go', 'detect', 'scan', 'activate'])) {
      return VoiceCommand.start;
    }
    if (_has(words, ['stop', 'end', 'off', 'pause', 'halt', 'cancel', 'finish', 'deactivate'])) {
      return VoiceCommand.stop;
    }
    if (_has(words, ['repeat', 'again', 'say again', 'what was that', 'pardon', 'what did'])) {
      return VoiceCommand.repeat;
    }
    if (_has(words, ['who', 'identify', 'name', 'face', 'recognize', 'recognise'])) {
      return VoiceCommand.whoIsThis;
    }
    if (_has(words, ['settings', 'setting', 'configure', 'options', 'preferences', 'config'])) {
      return VoiceCommand.openSettings;
    }
    if (_has(words, ['people', 'persons', 'faces', 'contacts', 'add person', 'manage'])) {
      return VoiceCommand.openPeople;
    }
    if (_has(words, ['help', 'commands', 'assist', 'guide', 'instructions', 'what can'])) {
      return VoiceCommand.help;
    }
    return VoiceCommand.unknown;
  }

  bool _has(String words, List<String> kw) => kw.any((k) => words.contains(k));

  void dispose() {
    _listening = false;
    SharedStt.instance.clearListeners();
    SharedStt.instance.stop();
  }
}
