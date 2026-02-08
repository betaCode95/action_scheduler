/// Configuration for pre-action notifications.
///
/// When attached to a scheduled action, a local notification will be
/// triggered [leadTime] before the actual action runs.
class NotificationConfig {
  /// Title of the notification.
  final String title;

  /// Body text of the notification.
  final String body;

  /// How long before the action to trigger the notification.
  ///
  /// For example, `Duration(hours: 24)` sends the notification
  /// 24 hours before the action runs.
  final Duration leadTime;

  /// Whether the notification is enabled.
  final bool enabled;

  const NotificationConfig({
    required this.title,
    required this.body,
    this.leadTime = const Duration(hours: 1),
    this.enabled = true,
  });

  /// Serializes to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'notifTitle': title,
      'notifBody': body,
      'leadTimeMinutes': leadTime.inMinutes,
      'notifEnabled': enabled ? 1 : 0,
    };
  }

  /// Deserializes from a database map.
  factory NotificationConfig.fromMap(Map<String, dynamic> map) {
    return NotificationConfig(
      title: map['notifTitle'] as String,
      body: map['notifBody'] as String,
      leadTime: Duration(minutes: map['leadTimeMinutes'] as int),
      enabled: (map['notifEnabled'] as int) == 1,
    );
  }

  /// Creates a copy with optional overrides.
  NotificationConfig copyWith({
    String? title,
    String? body,
    Duration? leadTime,
    bool? enabled,
  }) {
    return NotificationConfig(
      title: title ?? this.title,
      body: body ?? this.body,
      leadTime: leadTime ?? this.leadTime,
      enabled: enabled ?? this.enabled,
    );
  }

  @override
  String toString() =>
      'NotificationConfig(title: $title, leadTime: ${leadTime.inMinutes}min, enabled: $enabled)';
}
