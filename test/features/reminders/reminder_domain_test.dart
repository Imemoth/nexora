import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import '../../support/reminder_support.dart';

void main() {
  group('LocalWallTime', () {
    test('round-trips through its text form', () {
      const wall = LocalWallTime(2026, 11, 15, 9, 5);
      expect(wall.toIsoString(), '2026-11-15T09:05');
      expect(LocalWallTime.tryParse('2026-11-15T09:05'), wall);
    });

    test('rejects impossible or malformed text', () {
      for (final bad in [
        '2026-02-30T09:00',
        '2026-11-15T25:00',
        '2026-11-15T09:60',
        '2026-11-15 09:00',
        '15.11.2026 09:00',
        '',
      ]) {
        expect(LocalWallTime.tryParse(bad), isNull, reason: bad);
      }
    });

    test('orders chronologically', () {
      const a = LocalWallTime(2026, 11, 15, 9, 0);
      const b = LocalWallTime(2026, 11, 15, 9, 1);
      const c = LocalWallTime(2026, 12, 1, 0, 0);
      expect(a.compareTo(b), lessThan(0));
      expect(c.compareTo(b), greaterThan(0));
    });
  });

  group('time zone and daylight saving (fake New York zone)', () {
    final clock = FakeZoneClock(DateTime.utc(2026, 1, 1));

    test('a winter wall time resolves with the winter offset', () {
      expect(
        clock.resolve(const LocalWallTime(2026, 1, 15, 9, 0)),
        DateTime.utc(2026, 1, 15, 14),
      );
    });

    test('a summer wall time resolves with the summer offset', () {
      expect(
        clock.resolve(const LocalWallTime(2026, 7, 15, 9, 0)),
        DateTime.utc(2026, 7, 15, 13),
      );
    });

    test(
      'a time in the hour skipped by spring forward moves after the gap',
      () {
        // 02:30 does not exist on 2026-03-08; it fires at 03:30 local time.
        final instant = clock.resolve(const LocalWallTime(2026, 3, 8, 2, 30));
        expect(instant, DateTime.utc(2026, 3, 8, 7, 30));
        expect(clock.toLocal(instant), const LocalWallTime(2026, 3, 8, 3, 30));
      },
    );

    test('a repeated time on fall back resolves to its first occurrence', () {
      // 01:30 happens twice on 2026-11-01; the first one is still summer time.
      expect(
        clock.resolve(const LocalWallTime(2026, 11, 1, 1, 30)),
        DateTime.utc(2026, 11, 1, 5, 30),
      );
    });

    test('the chosen wall time keeps its meaning across the switch', () {
      // 09:00 the day before and the day after fall back are both 09:00 local,
      // although the UTC hour differs.
      final before = clock.resolve(const LocalWallTime(2026, 10, 31, 9, 0));
      final after = clock.resolve(const LocalWallTime(2026, 11, 2, 9, 0));
      expect(before.hour, 13);
      expect(after.hour, 14);
    });

    test(
      'a snoozed reminder fires at the snooze instant, not the wall time',
      () {
        final reminder = Reminder(
          taskId: 't',
          remindAt: const LocalWallTime(2026, 7, 15, 9, 0),
          state: ReminderState.scheduled,
          snoozeUntilUtc: DateTime.utc(2026, 7, 15, 15),
        );
        expect(reminder.dueUtc(clock), DateTime.utc(2026, 7, 15, 15));
      },
    );
  });

  test('the system clock converts a wall time and back', () {
    const clock = SystemReminderClock();
    const wall = LocalWallTime(2030, 6, 1, 12, 0);
    expect(clock.toLocal(clock.resolve(wall)), wall);
  });
}
