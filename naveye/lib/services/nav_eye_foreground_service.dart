import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Manages the Android Foreground Service that keeps NavEye alive
/// when the screen is locked or the user switches to another app.
///
/// The service shows a persistent notification so Android doesn't kill
/// the process. All detection / TTS code continues in the main isolate —
/// this class just manages the native service lifecycle.
class NavEyeForegroundService {
  static bool _initialized = false;

  // ── One-time configuration ─────────────────────────────────────────────────
  static void init() {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId:          'naveye_detection',
        channelName:        'NavEye Detection',
        channelDescription: 'NavEye obstacle detection is running in the background',
        channelImportance:  NotificationChannelImportance.LOW,
        priority:           NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound:        false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction:    ForegroundTaskEventAction.nothing(),
        autoRunOnBoot:  false,
        allowWakeLock:  true,   // prevent CPU sleep during detection
        allowWifiLock:  false,
      ),
    );
  }

  // ── Start ──────────────────────────────────────────────────────────────────
  static Future<void> start() async {
    try {
      if (await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.startService(
        serviceId:         256,
        notificationTitle: 'NavEye Active',
        notificationText:  'Obstacle detection is running',
      );
      debugPrint('NavEyeForegroundService: started');
    } catch (e) {
      debugPrint('NavEyeForegroundService start error: $e');
    }
  }

  // ── Update notification text with latest detection ─────────────────────────
  static Future<void> update({
    required String label,
    required String distance,
  }) async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'NavEye Active',
        notificationText:  '$label detected — $distance',
      );
    } catch (_) {}
  }

  // ── Clear notification (path clear) ───────────────────────────────────────
  static Future<void> clearDetection() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.updateService(
        notificationTitle: 'NavEye Active',
        notificationText:  'Scanning for obstacles...',
      );
    } catch (_) {}
  }

  // ── Stop ───────────────────────────────────────────────────────────────────
  static Future<void> stop() async {
    try {
      if (!await FlutterForegroundTask.isRunningService) return;
      await FlutterForegroundTask.stopService();
      debugPrint('NavEyeForegroundService: stopped');
    } catch (e) {
      debugPrint('NavEyeForegroundService stop error: $e');
    }
  }

  // ── Status ─────────────────────────────────────────────────────────────────
  static Future<bool> get isRunning async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }
}
