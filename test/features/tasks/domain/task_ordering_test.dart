import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';

import '../../../support/task_fixtures.dart';

List<String> _ids(Iterable<FlatTaskEntry> entries) {
  return [for (final entry in entries) entry.task.id];
}

List<String> _sortedIds(List<Task> tasks, TaskSort sort) {
  final copy = List<Task>.of(tasks);
  copy.sort((a, b) => compareTasks(a, b, sort));
  return [for (final task in copy) task.id];
}

void main() {
  group('compareTasks', () {
    test('position sort orders by position', () {
      final tasks = [
        makeTask(id: 'a', position: 2),
        makeTask(id: 'b', position: 0),
        makeTask(id: 'c', position: 1),
      ];

      expect(_sortedIds(tasks, TaskSort.position), ['b', 'c', 'a']);
    });

    test('equal positions are broken by id', () {
      final tasks = [
        makeTask(id: 'zeta', position: 1),
        makeTask(id: 'alpha', position: 1),
      ];

      expect(_sortedIds(tasks, TaskSort.position), ['alpha', 'zeta']);
    });

    test('due date sort puts undated tasks last', () {
      final tasks = [
        makeTask(id: 'none'),
        makeTask(id: 'late', dueDate: const CalendarDate(2026, 11, 20)),
        makeTask(id: 'early', dueDate: const CalendarDate(2026, 11, 12)),
      ];

      expect(_sortedIds(tasks, TaskSort.dueDate), ['early', 'late', 'none']);
    });

    test('priority sort ranks high, medium, low, then none', () {
      final tasks = [
        makeTask(id: 'low', priority: TaskPriority.low),
        makeTask(id: 'none', priority: TaskPriority.none),
        makeTask(id: 'high', priority: TaskPriority.high),
        makeTask(id: 'medium', priority: TaskPriority.medium),
      ];

      expect(_sortedIds(tasks, TaskSort.priority), [
        'high',
        'medium',
        'low',
        'none',
      ]);
    });

    test('title sort is case-insensitive', () {
      final tasks = [
        makeTask(id: '1', title: 'banana'),
        makeTask(id: '2', title: 'Apple'),
        makeTask(id: '3', title: 'cherry'),
      ];

      expect(_sortedIds(tasks, TaskSort.title), ['2', '1', '3']);
    });

    test('sorting the same input twice gives the same order', () {
      final tasks = [
        makeTask(id: 'b', position: 1),
        makeTask(id: 'a', position: 1),
        makeTask(id: 'c', position: 0),
      ];

      expect(
        _sortedIds(tasks, TaskSort.position),
        _sortedIds(tasks, TaskSort.position),
      );
    });
  });

  group('flattenTasks', () {
    // R (pos 0)
    //   C1 (pos 0)
    //     G (pos 0)
    //   C2 (pos 1)
    final tree = [
      makeTask(id: 'R', position: 0),
      makeTask(id: 'C2', parentId: 'R', position: 1),
      makeTask(id: 'C1', parentId: 'R', position: 0),
      makeTask(id: 'G', parentId: 'C1', position: 0),
    ];

    test('depth-first order with children sorted by position', () {
      final rows = flattenTasks(tasks: tree, sort: TaskSort.position);

      expect(_ids(rows), ['R', 'C1', 'G', 'C2']);
      expect([for (final r in rows) r.depth], [0, 1, 2, 1]);
    });

    test('reports whether each row has children', () {
      final rows = flattenTasks(tasks: tree, sort: TaskSort.position);

      expect([for (final r in rows) r.hasChildren], [true, true, false, false]);
    });

    test('hides children of collapsed rows', () {
      final rows = flattenTasks(
        tasks: tree,
        sort: TaskSort.position,
        expandedIds: {},
      );

      expect(_ids(rows), ['R']);
    });

    test('shows grandchildren only when the child is also expanded', () {
      final rows = flattenTasks(
        tasks: tree,
        sort: TaskSort.position,
        expandedIds: {'R'},
      );

      expect(_ids(rows), ['R', 'C1', 'C2']);
    });

    test('a task whose parent is outside the set becomes a root', () {
      final subset = [
        makeTask(id: 'C1', parentId: 'R', position: 0),
        makeTask(id: 'G', parentId: 'C1', position: 0),
      ];

      final rows = flattenTasks(tasks: subset, sort: TaskSort.position);

      expect(_ids(rows), ['C1', 'G']);
      expect([for (final r in rows) r.depth], [0, 1]);
    });

    test('a lone task with a missing parent is shown at depth 0', () {
      final lone = [makeTask(id: 'G', parentId: 'gone')];

      final rows = flattenTasks(tasks: lone, sort: TaskSort.position);

      expect(_ids(rows), ['G']);
      expect(rows.single.depth, 0);
    });

    test('produces the same order on repeated calls', () {
      final first = flattenTasks(tasks: tree, sort: TaskSort.position);
      final second = flattenTasks(tasks: tree, sort: TaskSort.position);

      expect(_ids(first), _ids(second));
    });
  });
}
