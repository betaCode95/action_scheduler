/// Defines the recurrence pattern for a scheduled action.
///
/// Supports daily, weekly, monthly, and custom interval schedules.
/// Each schedule specifies the exact time and recurrence pattern.
enum ScheduleType {
  /// Runs every day at a specific time.
  daily,

  /// Runs on a specific day of the week at a specific time.
  weekly,

  /// Runs on a specific day of the month at a specific time.
  monthly,

  /// Runs at a custom interval (e.g., every 2 days, every 3 hours).
  interval,
}

class Schedule {
  /// The type of recurrence.
  final ScheduleType type;

  /// Hour of day to run (0-23).
  final int hour;

  /// Minute of hour to run (0-59).
  final int minute;

  /// Day of week for weekly schedules (1=Monday, 7=Sunday).
  final int? dayOfWeek;

  /// Day of month for monthly schedules (1-31).
  final int? dayOfMonth;

  /// Custom interval duration for interval-based schedules.
  final Duration? interval;

  /// Creates a daily schedule at the specified time.
  ///
  /// Example: `Schedule.daily(hour: 9, minute: 0)` runs every day at 9:00 AM.
  const Schedule.daily({required this.hour, this.minute = 0})
      : type = ScheduleType.daily,
        dayOfWeek = null,
        dayOfMonth = null,
        interval = null;

  /// Creates a weekly schedule for a specific day and time.
  ///
  /// [day] uses ISO 8601: 1=Monday, 2=Tuesday, ..., 7=Sunday.
  ///
  /// Example: `Schedule.weekly(day: 1, hour: 9)` runs every Monday at 9:00 AM.
  const Schedule.weekly({required int day, required this.hour, this.minute = 0})
      : type = ScheduleType.weekly,
        dayOfWeek = day,
        dayOfMonth = null,
        interval = null;

  /// Creates a monthly schedule for a specific day of month and time.
  ///
  /// If [day] exceeds the number of days in a month, the action will run
  /// on the last day of that month.
  ///
  /// Example: `Schedule.monthly(day: 1, hour: 10)` runs on the 1st of every month at 10:00 AM.
  const Schedule.monthly(
      {required int day, required this.hour, this.minute = 0})
      : type = ScheduleType.monthly,
        dayOfMonth = day,
        dayOfWeek = null,
        interval = null;

  /// Creates an interval-based schedule.
  ///
  /// Example: `Schedule.every(Duration(hours: 6))` runs every 6 hours.
  Schedule.every(Duration every, {this.hour = 0, this.minute = 0})
      : type = ScheduleType.interval,
        interval = every,
        dayOfWeek = null,
        dayOfMonth = null;

  /// Internal constructor for deserialization.
  const Schedule._({
    required this.type,
    required this.hour,
    required this.minute,
    this.dayOfWeek,
    this.dayOfMonth,
    this.interval,
  });

  /// Serializes the schedule to a map for database storage.
  Map<String, dynamic> toMap() {
    return {
      'type': type.index,
      'hour': hour,
      'minute': minute,
      'dayOfWeek': dayOfWeek,
      'dayOfMonth': dayOfMonth,
      'intervalMinutes': interval?.inMinutes,
    };
  }

  /// Deserializes a schedule from a database map.
  factory Schedule.fromMap(Map<String, dynamic> map) {
    return Schedule._(
      type: ScheduleType.values[map['type'] as int],
      hour: map['hour'] as int,
      minute: map['minute'] as int,
      dayOfWeek: map['dayOfWeek'] as int?,
      dayOfMonth: map['dayOfMonth'] as int?,
      interval: map['intervalMinutes'] != null
          ? Duration(minutes: map['intervalMinutes'] as int)
          : null,
    );
  }

  /// Returns a human-readable description of the schedule.
  String get description {
    switch (type) {
      case ScheduleType.daily:
        return 'Every day at ${_formatTime(hour, minute)}';
      case ScheduleType.weekly:
        return 'Every ${_dayName(dayOfWeek!)} at ${_formatTime(hour, minute)}';
      case ScheduleType.monthly:
        return 'On the ${_ordinal(dayOfMonth!)} of every month at ${_formatTime(hour, minute)}';
      case ScheduleType.interval:
        return 'Every ${_formatDuration(interval!)}';
    }
  }

  static String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }

  static String _dayName(int day) {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return days[day - 1];
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  static String _formatDuration(Duration d) {
    if (d.inDays > 0) return '${d.inDays} day${d.inDays > 1 ? 's' : ''}';
    if (d.inHours > 0) return '${d.inHours} hour${d.inHours > 1 ? 's' : ''}';
    return '${d.inMinutes} minute${d.inMinutes > 1 ? 's' : ''}';
  }

  @override
  String toString() => 'Schedule($description)';
}
