import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

import '../../../support/task_fixtures.dart';

void main() {
  const today = CalendarDate(2026, 11, 16);

  group('DueTime', () {
    test('parses and prints 24-hour HH:MM', () {
      expect(DueTime.tryParse('09:05'), const DueTime(9, 5));
      expect(const DueTime(9, 5).toHm(), '09:05');
      expect(const DueTime(0, 0).toHm(), '00:00');
      expect(const DueTime(23, 59).toHm(), '23:59');
    });

    test('rejects anything that is not a valid wall time', () {
      for (final bad in ['24:00', '12:60', '9:05', '', '12', '12:5', '1200']) {
        expect(DueTime.tryParse(bad), isNull, reason: bad);
      }
      expect(DueTime.tryParse(null), isNull);
    });

    test('orders by time of day', () {
      expect(const DueTime(8, 0).compareTo(const DueTime(8, 1)), lessThan(0));
      expect(
        const DueTime(23, 0).compareTo(const DueTime(1, 0)),
        greaterThan(0),
      );
    });
  });

  group('Task: the time depends on the date', () {
    test('a date-only task has no time (not midnight)', () {
      final task = makeTask(id: 'a', dueDate: today);
      expect(task.dueTime, isNull);
    });

    test('clearing the date also clears the time', () {
      final task = makeTask(
        id: 'a',
        dueDate: today,
        dueTime: const DueTime(14, 30),
      );
      final cleared = task.copyWith(clearDueDate: true);
      expect(cleared.dueDate, isNull);
      expect(cleared.dueTime, isNull);
    });

    test('clearing only the time keeps the date', () {
      final task = makeTask(
        id: 'a',
        dueDate: today,
        dueTime: const DueTime(14, 30),
      );
      final cleared = task.copyWith(clearDueTime: true);
      expect(cleared.dueDate, today);
      expect(cleared.dueTime, isNull);
    });

    test('changing the date keeps the time', () {
      final task = makeTask(
        id: 'a',
        dueDate: today,
        dueTime: const DueTime(14, 30),
      );
      final moved = task.copyWith(dueDate: today.addDays(3));
      expect(moved.dueTime, const DueTime(14, 30));
    });

    test('a time without a date cannot be built', () {
      expect(
        () => makeTask(id: 'a', dueTime: const DueTime(9, 0)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('sorting by due date', () {
    int cmp(a, b) => compareTasks(a, b, TaskSort.dueDate);

    test('existing date-only tasks sort exactly as before', () {
      final a = makeTask(id: 'a', dueDate: today, position: 1);
      final b = makeTask(id: 'b', dueDate: today, position: 0);
      final c = makeTask(id: 'c', dueDate: today.addDays(-1), position: 5);
      final none = makeTask(id: 'n', position: 0);
      final sorted = [a, b, none, c]..sort(cmp);
      expect(sorted.map((t) => t.id), ['c', 'b', 'a', 'n']);
    });

    test('on one date: earlier time first, then later, then date-only', () {
      final late = makeTask(
        id: 'late',
        dueDate: today,
        dueTime: const DueTime(17, 0),
      );
      final early = makeTask(
        id: 'early',
        dueDate: today,
        dueTime: const DueTime(8, 30),
      );
      final dateOnly = makeTask(id: 'day', dueDate: today, position: 0);
      final sorted = [dateOnly, late, early]..sort(cmp);
      expect(sorted.map((t) => t.id), ['early', 'late', 'day']);
    });

    test('a later date still wins over an earlier time', () {
      final tomorrowEarly = makeTask(
        id: 't',
        dueDate: today.addDays(1),
        dueTime: const DueTime(0, 0),
      );
      final todayLate = makeTask(
        id: 'n',
        dueDate: today,
        dueTime: const DueTime(23, 59),
      );
      expect(cmp(todayLate, tomorrowEarly), lessThan(0));
    });
  });

  group('filtering stays date based', () {
    test('a timed task due today is in Today and not Overdue all day', () {
      final task = makeTask(
        id: 'a',
        dueDate: today,
        dueTime: const DueTime(0, 1),
      );
      expect(matchesSmartView(task, SmartView.today, today), isTrue);
      expect(matchesSmartView(task, SmartView.overdue, today), isFalse);
    });

    test('a timed task from yesterday is Overdue, like a date-only one', () {
      final task = makeTask(
        id: 'a',
        dueDate: today.addDays(-1),
        dueTime: const DueTime(23, 59),
      );
      expect(matchesSmartView(task, SmartView.overdue, today), isTrue);
    });
  });

  group('display', () {
    test('a date-only deadline shows no time', () {
      expect(
        AppStrings.friendlyDue(today, today, closed: false),
        AppStrings.dueToday,
      );
    });

    test('a deadline with a time appends it', () {
      expect(
        AppStrings.friendlyDue(
          today,
          today,
          closed: false,
          time: const DueTime(9, 5),
        ),
        '${AppStrings.dueToday} · 09:05',
      );
      expect(
        AppStrings.friendlyDue(
          const CalendarDate(2026, 11, 20),
          today,
          closed: false,
          time: const DueTime(17, 30),
        ),
        'Fri 20 Nov · 17:30',
      );
    });
  });

  group('time zone and daylight saving: floating wall-clock semantics', () {
    test('a date-only value never shifts to another day', () {
      // 23:59 local on the day the clocks go forward or back, and at the
      // new-year boundary: the calendar day is read as written, with no UTC
      // conversion that could move it.
      for (final local in [
        DateTime(2026, 3, 8, 23, 59),
        DateTime(2026, 10, 25, 0, 0),
        DateTime(2026, 12, 31, 23, 59),
        DateTime(2026, 1, 1, 0, 0),
      ]) {
        final date = CalendarDate.fromDateTime(local);
        expect(date, CalendarDate(local.year, local.month, local.day));
        expect(date.toIsoString(), local.toIso8601String().substring(0, 10));
      }
    });

    test('a time is stored and shown as written, including a skipped hour', () {
      // 02:30 does not exist on a spring-forward day in some zones. The value
      // is a label, not an instant: it is kept and shown unchanged.
      const skipped = DueTime(2, 30);
      expect(DueTime.tryParse(skipped.toHm()), skipped);
      expect(skipped.toHm(), '02:30');
    });

    test('the same stored value reads the same in any zone', () {
      // Nothing in the value depends on a zone, so a zone change cannot move it.
      final stored = const DueTime(17, 30).toHm();
      expect(stored, '17:30');
      expect(DueTime.tryParse(stored)!.minutesOfDay, 17 * 60 + 30);
    });
  });
}
