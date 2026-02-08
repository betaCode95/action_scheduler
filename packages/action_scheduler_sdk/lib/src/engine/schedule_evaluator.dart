import '../models/schedule.dart';

/// Computes next run times for scheduled actions based on their recurrence rules.
///
/// This is a pure computation class with no side effects, making it
/// easy to test and reason about.
class ScheduleEvaluator {
  /// Computes the next run time for a given schedule, starting from [from].
  ///
  /// If [from] is null, uses the current time. The returned time is always
  /// strictly in the future relative to [from].
  static DateTime computeNextRun(Schedule schedule, {DateTime? from}) {
    final now = from ?? DateTime.now();

    switch (schedule.type) {
      case ScheduleType.daily:
        return _nextDaily(now, schedule.hour, schedule.minute);

      case ScheduleType.weekly:
        return _nextWeekly(
          now,
          schedule.dayOfWeek!,
          schedule.hour,
          schedule.minute,
        );

      case ScheduleType.monthly:
        return _nextMonthly(
          now,
          schedule.dayOfMonth!,
          schedule.hour,
          schedule.minute,
        );

      case ScheduleType.interval:
        return now.add(schedule.interval!);
    }
  }

  /// Checks if a scheduled action is due to run (i.e., its next run time
  /// is at or before the current time).
  static bool isDue(DateTime nextRunAt, {DateTime? now}) {
    final current = now ?? DateTime.now();
    return !nextRunAt.isAfter(current);
  }

  /// Computes all missed run times between [lastRunAt] and [now] for a schedule.
  ///
  /// This is used during startup recovery to identify and log missed executions.
  static List<DateTime> computeMissedRuns(
    Schedule schedule, {
    required DateTime lastRunAt,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final missed = <DateTime>[];

    var next = computeNextRun(schedule, from: lastRunAt);
    while (next.isBefore(current)) {
      missed.add(next);
      next = computeNextRun(schedule, from: next);
    }

    return missed;
  }

  // --- Private helpers ---

  static DateTime _nextDaily(DateTime from, int hour, int minute) {
    var next = DateTime(from.year, from.month, from.day, hour, minute);
    if (!next.isAfter(from)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  static DateTime _nextWeekly(
      DateTime from, int targetDay, int hour, int minute) {
    var next = DateTime(from.year, from.month, from.day, hour, minute);

    if (next.weekday == targetDay && !next.isAfter(from)) {
      next = next.add(const Duration(days: 7));
    } else {
      while (next.weekday != targetDay || !next.isAfter(from)) {
        next = next.add(const Duration(days: 1));
      }
    }

    return next;
  }

  static DateTime _nextMonthly(
      DateTime from, int targetDay, int hour, int minute) {
    int clampedDay = _clampDay(from.year, from.month, targetDay);
    var next = DateTime(from.year, from.month, clampedDay, hour, minute);

    if (!next.isAfter(from)) {
      int nextMonth = from.month + 1;
      int nextYear = from.year;
      if (nextMonth > 12) {
        nextMonth = 1;
        nextYear++;
      }
      clampedDay = _clampDay(nextYear, nextMonth, targetDay);
      next = DateTime(nextYear, nextMonth, clampedDay, hour, minute);
    }

    return next;
  }

  /// Clamps the day to the maximum number of days in the given month.
  static int _clampDay(int year, int month, int day) {
    final maxDays = DateTime(year, month + 1, 0).day;
    return day > maxDays ? maxDays : day;
  }
}
