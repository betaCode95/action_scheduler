import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/scheduled_action.dart';

/// Manages local notifications for pre-action reminders.
///
/// Handles initialization of the notification plugin, scheduling
/// notifications ahead of action execution times, and cancellation.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Callback invoked when a notification is tapped.
  void Function(String? actionId)? onNotificationTapped;

  /// Initializes the notification plugin for both Android and iOS.
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone data
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Request permissions on iOS
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    // Request permissions on Android 13+
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  void _onNotificationResponse(NotificationResponse response) {
    onNotificationTapped?.call(response.payload);
  }

  /// Schedules a notification before an action's next run.
  ///
  /// The notification fires at `nextRunAt - leadTime`.
  /// If that time is already in the past, the notification is skipped.
  Future<void> scheduleForAction(ScheduledAction action) async {
    if (!_initialized) return;
    if (action.notification == null || !action.notification!.enabled) return;
    if (action.nextRunAt == null) return;

    final config = action.notification!;
    final notifyAt = action.nextRunAt!.subtract(config.leadTime);

    // Don't schedule if notification time has already passed
    if (notifyAt.isBefore(DateTime.now())) return;

    final notificationId = action.id.hashCode;

    await _plugin.zonedSchedule(
      notificationId,
      config.title,
      config.body,
      tz.TZDateTime.from(notifyAt, tz.local),
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: action.id,
      matchDateTimeComponents: null,
    );
  }

  /// Cancels any pending notification for an action.
  Future<void> cancelForAction(String actionId) async {
    if (!_initialized) return;
    await _plugin.cancel(actionId.hashCode);
  }

  /// Cancels all pending notifications.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// Shows an immediate notification (useful for testing).
  Future<void> showImmediate({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      _notificationDetails(),
      payload: payload,
    );
  }

  NotificationDetails _notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'action_scheduler_channel',
        'Action Scheduler',
        channelDescription: 'Notifications for scheduled action reminders',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  /// Reschedules notifications for all provided actions.
  Future<void> rescheduleAll(List<ScheduledAction> actions) async {
    await cancelAll();
    for (final action in actions) {
      if (action.isActive) {
        await scheduleForAction(action);
      }
    }
  }
}
