import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/task_fixtures.dart';

const _today = CalendarDate(2026, 11, 11);

CalendarDate _offset(int days) => _today.addDays(days);

void main() {
  group('matchesSmartView', () {
    test('open task due today is in Today, not in other date views', () {
      final task = makeTask(id: 't', dueDate: _today);

      expect(matchesSmartView(task, SmartView.today, _today), isTrue);
      expect(matchesSmartView(task, SmartView.next7Days, _today), isFalse);
      expect(matchesSmartView(task, SmartView.overdue, _today), isFalse);
      expect(matchesSmartView(task, SmartView.all, _today), isTrue);
    });

    test('tomorrow is in Next 7 Days', () {
      final task = makeTask(id: 't', dueDate: _offset(1));

      expect(matchesSmartView(task, SmartView.next7Days, _today), isTrue);
      expect(matchesSmartView(task, SmartView.today, _today), isFalse);
    });

    test('today plus 7 is the last day in Next 7 Days', () {
      final task = makeTask(id: 't', dueDate: _offset(7));

      expect(matchesSmartView(task, SmartView.next7Days, _today), isTrue);
    });

    test('today plus 8 is outside Next 7 Days', () {
      final task = makeTask(id: 't', dueDate: _offset(8));

      expect(matchesSmartView(task, SmartView.next7Days, _today), isFalse);
      expect(matchesSmartView(task, SmartView.overdue, _today), isFalse);
    });

    test('yesterday is overdue and not in Today', () {
      final task = makeTask(id: 't', dueDate: _offset(-1));

      expect(matchesSmartView(task, SmartView.overdue, _today), isTrue);
      expect(matchesSmartView(task, SmartView.today, _today), isFalse);
      expect(matchesSmartView(task, SmartView.next7Days, _today), isFalse);
    });

    test('a task due today is not overdue', () {
      final task = makeTask(id: 't', dueDate: _today);

      expect(matchesSmartView(task, SmartView.overdue, _today), isFalse);
    });

    test('a task without a due date appears only in All', () {
      final task = makeTask(id: 't');

      expect(matchesSmartView(task, SmartView.today, _today), isFalse);
      expect(matchesSmartView(task, SmartView.next7Days, _today), isFalse);
      expect(matchesSmartView(task, SmartView.overdue, _today), isFalse);
      expect(matchesSmartView(task, SmartView.all, _today), isTrue);
    });

    test('done tasks are excluded from every view except All', () {
      final task = makeTask(id: 't', dueDate: _today, status: TaskStatus.done);

      expect(matchesSmartView(task, SmartView.today, _today), isFalse);
      expect(matchesSmartView(task, SmartView.all, _today), isTrue);
    });

    test('archived overdue tasks are excluded from Overdue but in All', () {
      final task = makeTask(
        id: 't',
        dueDate: _offset(-3),
        status: TaskStatus.archived,
      );

      expect(matchesSmartView(task, SmartView.overdue, _today), isFalse);
      expect(matchesSmartView(task, SmartView.all, _today), isTrue);
    });

    test('in-progress and review tasks count as open', () {
      final inProgress = makeTask(
        id: 'ip',
        dueDate: _today,
        status: TaskStatus.inProgress,
      );
      final review = makeTask(
        id: 'rv',
        dueDate: _offset(-1),
        status: TaskStatus.review,
      );

      expect(matchesSmartView(inProgress, SmartView.today, _today), isTrue);
      expect(matchesSmartView(review, SmartView.overdue, _today), isTrue);
    });
  });
}
