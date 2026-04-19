import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'tts_service.dart';

/// Monitors battery level and network connectivity, speaking alerts
/// through TTS when important state changes occur.
class SystemMonitorService {
  final TtsService _tts;

  final _battery      = Battery();
  final _connectivity = Connectivity();

  StreamSubscription<BatteryState>?          _batterySub;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool _warned20 = false;
  bool _warned10 = false;
  bool _wasOnline = true;

  SystemMonitorService(this._tts);

  // ── Start monitoring ───────────────────────────────────────────────────────
  Future<void> start() async {
    // ── Connectivity: check initial state ────────────────────────────────────
    try {
      final initial = await _connectivity.checkConnectivity();
      _wasOnline = !initial.contains(ConnectivityResult.none);
    } catch (_) {}

    // ── Connectivity: listen for changes ─────────────────────────────────────
    _connSub = _connectivity.onConnectivityChanged.listen((results) async {
      final online = !results.contains(ConnectivityResult.none);
      if (_wasOnline && !online) {
        _wasOnline = false;
        debugPrint('SystemMonitor: connectivity lost');
        await _tts.announce('Internet connection lost. Using offline mode.');
      } else if (!_wasOnline && online) {
        _wasOnline = true;
        debugPrint('SystemMonitor: connectivity restored');
        await _tts.announce('Internet connection restored.');
      }
    });

    // ── Battery: check initial level ─────────────────────────────────────────
    try {
      final level = await _battery.batteryLevel;
      debugPrint('SystemMonitor: initial battery $level%');
    } catch (_) {}

    // ── Battery: listen for state changes ────────────────────────────────────
    _batterySub = _battery.onBatteryStateChanged.listen((_) async {
      try {
        final state = await _battery.batteryState;
        // Reset warnings when plugged in
        if (state == BatteryState.charging ||
            state == BatteryState.full) {
          _warned20 = false;
          _warned10 = false;
          return;
        }
        final level = await _battery.batteryLevel;
        if (level <= 10 && !_warned10) {
          _warned10 = true;
          debugPrint('SystemMonitor: battery critical $level%');
          await _tts.speakNow(
              'Warning: Battery at $level percent. Please charge immediately.');
        } else if (level <= 20 && !_warned20) {
          _warned20 = true;
          debugPrint('SystemMonitor: battery low $level%');
          await _tts.announce(
              'Battery low: $level percent remaining. Please charge soon.');
        }
      } catch (e) {
        debugPrint('SystemMonitor battery error: $e');
      }
    });

    debugPrint('SystemMonitorService: started');
  }

  // ── Speak current battery level on demand ─────────────────────────────────
  Future<void> announceBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final stateStr = state == BatteryState.charging ? ', charging'
                     : state == BatteryState.full     ? ', fully charged'
                     : '';
      await _tts.speakNow('Battery is at $level percent$stateStr.');
    } catch (_) {
      await _tts.speakNow('Could not read battery level.');
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────
  void dispose() {
    _batterySub?.cancel();
    _connSub?.cancel();
    debugPrint('SystemMonitorService: disposed');
  }
}
