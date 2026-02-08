import 'notification_config.dart';
import 'schedule.dart';

/// Represents a registered scheduled action.
///
/// An action consists of:
/// - A unique [id] and human-readable [name]
/// - A [schedule] that defines the recurrence pattern
/// - Optional [notification] configuration for pre-action reminders
/// - State tracking ([isActive], [lastRunAt], [nextRunAt])
class ScheduledAction {
  /// Unique identifier for this action.
  final String id;

  /// Human-readable name of the action.
  final String name;

  /// Optional description of what this action does.
  final String? description;

  /// The recurrence schedule for this action.
  final Schedule schedule;

  /// Whether this action is currently active and will be executed.
  final bool isActive;

  /// When this action was first registered.
  final DateTime createdAt;

  /// When this action last ran (null if never run).
  final DateTime? lastRunAt;

  /// When this action is next scheduled to run.
  final DateTime? nextRunAt;

  /// Optional notification configuration for pre-action reminders.
  final NotificationConfig? notification;

  /// Optional metadata map for developer-specific data.
  final Map<String, String>? metadata;

  ScheduledAction({
    required this.id,
    required this.name,
    this.description,
    required this.schedule,
    this.isActive = true,
    DateTime? createdAt,
    this.lastRunAt,
    this.nextRunAt,
    this.notification,
    this.metadata,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Serializes to a map for database storage.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'isActive': isActive ? 1 : 0,
      'createdAt': createdAt.toIso8601String(),
      'lastRunAt': lastRunAt?.toIso8601String(),
      'nextRunAt': nextRunAt?.toIso8601String(),
      // Flatten schedule fields
      ...schedule.toMap(),
      // Flatten notification fields (if present)
      ...?notification?.toMap(),
      'hasNotification': notification != null ? 1 : 0,
      // Metadata as comma-separated key=value
      'metadata': metadata?.entries.map((e) => '${e.key}=${e.value}').join(','),
    };
    return map;
  }

  /// Deserializes from a database map.
  factory ScheduledAction.fromMap(Map<String, dynamic> map) {
    NotificationConfig? notification;
    if ((map['hasNotification'] as int?) == 1) {
      notification = NotificationConfig.fromMap(map);
    }

    Map<String, String>? metadata;
    if (map['metadata'] != null && (map['metadata'] as String).isNotEmpty) {
      metadata = {};
      for (final pair in (map['metadata'] as String).split(',')) {
        final parts = pair.split('=');
        if (parts.length == 2) {
          metadata[parts[0]] = parts[1];
        }
      }
    }

    return ScheduledAction(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      schedule: Schedule.fromMap(map),
      isActive: (map['isActive'] as int) == 1,
      createdAt: DateTime.parse(map['createdAt'] as String),
      lastRunAt: map['lastRunAt'] != null
          ? DateTime.parse(map['lastRunAt'] as String)
          : null,
      nextRunAt: map['nextRunAt'] != null
          ? DateTime.parse(map['nextRunAt'] as String)
          : null,
      notification: notification,
      metadata: metadata,
    );
  }

  /// Creates a copy with optional field overrides.
  ScheduledAction copyWith({
    String? id,
    String? name,
    String? description,
    Schedule? schedule,
    bool? isActive,
    DateTime? createdAt,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    NotificationConfig? notification,
    Map<String, String>? metadata,
    bool clearNotification = false,
  }) {
    return ScheduledAction(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      schedule: schedule ?? this.schedule,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      notification: clearNotification ? null : (notification ?? this.notification),
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  String toString() =>
      'ScheduledAction(id: $id, name: $name, schedule: ${schedule.description}, active: $isActive)';
}
