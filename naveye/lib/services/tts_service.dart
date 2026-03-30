import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;
  String _lastAnnouncement = '';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final volume = prefs.getString('voice_volume') ?? 'Medium';
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(volume == 'High' ? 1.0 : volume == 'Low' ? 0.3 : 0.7);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => _isSpeaking = false);
  }

  Future<void> speak(String text) async {
    if (_isSpeaking && text == _lastAnnouncement) return;
    _lastAnnouncement = text;
    _isSpeaking = true;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  void dispose() {
    _tts.stop();
  }
}
