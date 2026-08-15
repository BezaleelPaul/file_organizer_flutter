import 'package:file_organizer/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleJob.nextRun', () {
    test('interval adds interval hours to last run', () {
      final job = ScheduleJob(root: '/x', mode: 'interval', intervalHours: 6)
        ..lastRun = DateTime(2026, 8, 1, 10).toIso8601String();
      expect(job.nextRun(DateTime(2026, 8, 1, 14)),
          DateTime(2026, 8, 1, 16));
    });

    test('daily runs today when still in the future', () {
      final job = ScheduleJob(root: '/x', mode: 'daily', hour: 18, minute: 30);
      final now = DateTime(2026, 8, 1, 10);
      expect(job.nextRun(now), DateTime(2026, 8, 1, 18, 30));
    });

    test('daily rolls to tomorrow when the time has passed', () {
      final job = ScheduleJob(root: '/x', mode: 'daily', hour: 18, minute: 30);
      final now = DateTime(2026, 8, 1, 20);
      expect(job.nextRun(now), DateTime(2026, 8, 2, 18, 30));
    });

    test('weekly picks the next selected weekday', () {
      final job = ScheduleJob(
        root: '/x',
        mode: 'weekly',
        hour: 9,
        minute: 0,
        weekdays: [6, 7], // Sat, Sun
      );
      // Friday 2026-08-14 → next is Saturday 2026-08-15 09:00.
      final now = DateTime(2026, 8, 14, 12);
      expect(job.nextRun(now), DateTime(2026, 8, 15, 9));
    });

    test('weekly on the same day before the time runs today', () {
      final job = ScheduleJob(
        root: '/x',
        mode: 'weekly',
        hour: 9,
        minute: 0,
        weekdays: [6],
      );
      final now = DateTime(2026, 8, 15, 8); // Saturday morning
      expect(job.nextRun(now), DateTime(2026, 8, 15, 9));
    });

    test('weekly with no weekdays means every day', () {
      final job = ScheduleJob(root: '/x', mode: 'weekly', hour: 9);
      final now = DateTime(2026, 8, 14, 12);
      expect(job.nextRun(now), DateTime(2026, 8, 15, 9));
    });
  });

  group('ScheduleJob.describe', () {
    test('interval', () {
      expect(
          ScheduleJob(
                  root: '/x',
                  mode: 'interval',
                  intervalHours: 6,
                  byExtension: false)
              .describe(),
          'Every 6 h');
    });

    test('daily', () {
      expect(
          ScheduleJob(
                  root: '/x',
                  mode: 'daily',
                  hour: 2,
                  minute: 0,
                  byExtension: false)
              .describe(),
          'Daily at 2:00');
    });

    test('weekly', () {
      final job = ScheduleJob(
        root: '/x',
        mode: 'weekly',
        hour: 9,
        minute: 5,
        weekdays: [1, 3, 5],
        byExtension: false,
      );
      expect(job.describe(), 'Mon, Wed, Fri at 9:05');
    });

    test('includes sort flags', () {
      final job = ScheduleJob(
        root: '/x',
        mode: 'interval',
        byExtension: true,
        bySize: true,
        byDate: false,
      );
      expect(job.describe(), 'Every 6 h (extension+size)');
    });
  });

  group('ScheduleJob JSON', () {
    test('round-trips', () {
      final job = ScheduleJob(
        root: '/x',
        mode: 'weekly',
        hour: 7,
        minute: 30,
        weekdays: [1, 2],
        byExtension: false,
        bySize: true,
        byDate: true,
      );
      final restored = ScheduleJob.fromJson(job.toJson());
      expect(restored.root, '/x');
      expect(restored.mode, 'weekly');
      expect(restored.hour, 7);
      expect(restored.minute, 30);
      expect(restored.weekdays, [1, 2]);
      expect(restored.byExtension, isFalse);
      expect(restored.bySize, isTrue);
      expect(restored.byDate, isTrue);
    });
  });
}