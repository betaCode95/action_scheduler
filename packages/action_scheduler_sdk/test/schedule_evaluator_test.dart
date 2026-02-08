import 'package:flutter_test/flutter_test.dart';

import 'package:action_scheduler_sdk/action_scheduler_sdk.dart';

void main() {
  group('ScheduleEvaluator', () {
    test('daily schedule returns next day if time has passed', () {
      const schedule = Schedule.daily(hour: 9, minute: 0);
      final from = DateTime(2025, 6, 15, 10, 0);

      final nextRun = ScheduleEvaluator.computeNextRun(schedule, from: from);

      expect(nextRun, DateTime(2025, 6, 16, 9, 0));
    });

    test('daily schedule returns today if time has not passed', () {
      const schedule = Schedule.daily(hour: 14, minute: 30);
      final from = DateTime(2025, 6, 15, 10, 0);

      final nextRun = ScheduleEvaluator.computeNextRun(schedule, from: from);

      expect(nextRun, DateTime(2025, 6, 15, 14, 30));
    });

    test('weekly schedule finds correct next day', () {
      const schedule = Schedule.weekly(day: 1, hour: 9, minute: 0);
      final from = DateTime(2025, 6, 15, 10, 0); // Sunday

      final nextRun = ScheduleEvaluator.computeNextRun(schedule, from: from);

      expect(nextRun.weekday, 1);
      expect(nextRun, DateTime(2025, 6, 16, 9, 0));
    });

    test('monthly schedule returns next month if day has passed', () {
      const schedule = Schedule.monthly(day: 1, hour: 10, minute: 0);
      final from = DateTime(2025, 6, 15, 10, 0);

      final nextRun = ScheduleEvaluator.computeNextRun(schedule, from: from);

      expect(nextRun, DateTime(2025, 7, 1, 10, 0));
    });

    test('monthly schedule clamps day for short months', () {
      const schedule = Schedule.monthly(day: 31, hour: 10, minute: 0);
      final from = DateTime(2025, 2, 1, 0, 0);

      final nextRun = ScheduleEvaluator.computeNextRun(schedule, from: from);

      expect(nextRun, DateTime(2025, 2, 28, 10, 0));
    });

    test('computeMissedRuns returns all missed times', () {
      const schedule = Schedule.daily(hour: 9, minute: 0);
      final lastRun = DateTime(2025, 6, 10, 9, 0);
      final now = DateTime(2025, 6, 13, 10, 0);

      final missed = ScheduleEvaluator.computeMissedRuns(
        schedule,
        lastRunAt: lastRun,
        now: now,
      );

      expect(missed.length, 3);
      expect(missed[0], DateTime(2025, 6, 11, 9, 0));
      expect(missed[1], DateTime(2025, 6, 12, 9, 0));
      expect(missed[2], DateTime(2025, 6, 13, 9, 0));
    });
  });

  group('Schedule description', () {
    test('daily description', () {
      const schedule = Schedule.daily(hour: 9, minute: 0);
      expect(schedule.description, 'Every day at 9:00 AM');
    });

    test('weekly description', () {
      const schedule = Schedule.weekly(day: 1, hour: 9, minute: 0);
      expect(schedule.description, 'Every Monday at 9:00 AM');
    });

    test('monthly description', () {
      const schedule = Schedule.monthly(day: 1, hour: 10, minute: 0);
      expect(schedule.description, 'On the 1st of every month at 10:00 AM');
    });
  });
}
