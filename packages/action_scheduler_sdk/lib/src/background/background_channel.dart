import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform channel wrapper for native background scheduling.
///
/// Communicates with Android (AlarmManager) and iOS (BGTaskScheduler)
/// to schedule/cancel exact-time alarms that fire even when the app is closed.
class BackgroundChannel {
  static const MethodChannel _channel =
      MethodChannel('com.actionscheduler.sdk/background');

  /// Checks if exact alarm scheduling is permitted on the current platform.
  ///
  /// On Android 12+ (API 31), `SCHEDULE_EXACT_ALARM` is a special permission
  /// that must be granted by the user in system settings. On older Android
  /// versions and on iOS, this always returns true.
  static Future<bool> canScheduleExactAlarms() async {
    // Only relevant on Android
    if (!Platform.isAndroid) return true;

    try {
      final result = await _channel.invokeMethod<bool>('canScheduleExactAlarms');
      debugPrint('[ActionSchedulerSDK] canScheduleExactAlarms: $result');
      return result ?? false;
    } catch (e) {
      debugPrint('[ActionSchedulerSDK] canScheduleExactAlarms error: $e');
      // If we can't check, assume permission is NOT granted so the dialog shows
      return false;
    }
  }

  /// Opens the system settings page where the user can grant the exact alarm
  /// permission (Android 12+ only). Has no effect on iOS or older Android.
  static Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } catch (e) {
      debugPrint('[ActionSchedulerSDK] openExactAlarmSettings error: $e');
    }
  }

  /// Registers the Dart callback dispatcher with native code.
  ///
  /// The [callbackHandle] is obtained from [PluginUtilities.getCallbackHandle]
  /// on the top-level background callback function. Native code stores this
  /// handle and uses it to start a headless Flutter engine when an alarm fires.
  static Future<void> registerCallbackDispatcher(
      CallbackHandle callbackHandle) async {
    await _channel.invokeMethod('registerCallbackDispatcher', {
      'callbackHandle': callbackHandle.toRawHandle(),
    });
  }

  /// Schedules a native exact-time alarm for the given action.
  ///
  /// On Android: Uses AlarmManager.setExactAndAllowWhileIdle()
  /// On iOS: Uses BGTaskScheduler.submit() with earliestBeginDate
  ///
  /// [requestCode] is a unique integer ID for this alarm (use action.id.hashCode).
  /// [triggerAtMillis] is the Unix epoch millisecond time to trigger.
  static Future<void> scheduleAlarm({
    required int requestCode,
    required int triggerAtMillis,
  }) async {
    await _channel.invokeMethod('scheduleAlarm', {
      'requestCode': requestCode,
      'triggerAtMillis': triggerAtMillis,
    });
  }

  /// Cancels a pending native alarm.
  static Future<void> cancelAlarm({required int requestCode}) async {
    await _channel.invokeMethod('cancelAlarm', {
      'requestCode': requestCode,
    });
  }

  /// Called from the headless callback dispatcher to signal completion.
  static Future<void> backgroundTaskComplete() async {
    await _channel.invokeMethod('backgroundTaskComplete');
  }

  /// Sets up a method call handler for calls FROM native TO Dart.
  ///
  /// Used in the headless isolate to receive the "executeBackgroundTask" call.
  static void setMethodCallHandler(
      Future<dynamic> Function(MethodCall call)? handler) {
    _channel.setMethodCallHandler(handler);
  }
}
