import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_error.dart';

/// App-wide STT singleton.
/// Android only allows ONE SpeechToText initialised at a time.
/// All widgets and services MUST use this — never create their own SpeechToText.
class SharedStt {
  static final SharedStt _i = SharedStt._();
  static SharedStt get instance => _i;
  SharedStt._();

  final SpeechToText _stt = SpeechToText();
  bool _initialized = false;
  bool _available   = false;
  Completer<bool>? _initCompleter;

  // ── Error listener — callers register before listen(), clear after done ──
  void Function(SpeechRecognitionError)? _errorListener;
  void Function(String)? _statusListener;

  void setErrorListener(void Function(SpeechRecognitionError) fn) {
    _errorListener = fn;
  }

  void setStatusListener(void Function(String) fn) {
    _statusListener = fn;
  }

  void clearListeners() {
    _errorListener  = null;
    _statusListener = null;
  }

  /// Force a full re-initialisation — call this after the user grants mic permission.
  void reset() {
    _initialized    = false;
    _available      = false;
    _initCompleter  = null;
  }

  Future<bool> init() async {
    if (_initialized) return _available;
    if (_initCompleter != null) return _initCompleter!.future;
    _initCompleter = Completer<bool>();
    debugPrint('SharedStt: initializing speech engine...');
    try {
      _available = await _stt.initialize(
        onError:  (e) {
          debugPrint('STT error: ${e.errorMsg}');
          _errorListener?.call(e);
        },
        onStatus: (s) {
          debugPrint('STT status: $s');
          _statusListener?.call(s);
        },
      );
      _initialized = true;
      debugPrint('SharedStt: initialized — available=$_available');
      _initCompleter!.complete(_available);
    } catch (e) {
      debugPrint('STT init exception: $e');
      _available   = false;
      _initialized = true;
      _initCompleter!.complete(false);
    }
    return _available;
  }

  SpeechToText get raw    => _stt;
  bool get available      => _available;
  bool get isListening    => _stt.isListening;

  Future<void> stop() async {
    try { await _stt.stop(); } catch (_) {}
  }

  Future<void> cancel() async {
    try { await _stt.cancel(); } catch (_) {}
  }
}
