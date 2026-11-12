import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/workspace_harness.dart';

List<String> _fingerprint(DemoData data) => [
  for (final t in data.tasks)
    '${t.id}|${t.projectId}|${t.parentId}|${t.title}|${t.status.name}|'
        '${t.priority.name}|${t.dueDate?.toIsoString()}|${t.notes}|${t.position}',
];

void main() {
  group('buildDemoData', () {
    test('is deterministic for the same date', () {
      final first = buildDemoData(testToday);
      final second = buildDemoData(testToday);

      expect(_fingerprint(first), _fingerprint(second));
      expect(first.projects.map((p) => p.id), second.projects.map((p) => p.id));
    });

    test('has unique ids and parents in the same project', () {
      final data = buildDemoData(testToday);
      final byId = {for (final t in data.tasks) t.id: t};
      final projectIds = {for (final p in data.projects) p.id};

      expect(byId.length, data.tasks.length);
      for (final task in data.tasks) {
        expect(projectIds, contains(task.projectId));
        final parentId = task.parentId;
        if (parentId != null) {
          expect(byId[parentId]?.projectId, task.projectId, reason: task.id);
        }
      }
    });

    test('sibling positions are unique within each parent group', () {
      final data = buildDemoData(testToday);
      final groups = <String, List<int>>{};
      for (final t in data.tasks) {
        groups
            .putIfAbsent('${t.projectId}/${t.parentId}', () => <int>[])
            .add(t.position);
      }

      for (final entry in groups.entries) {
        expect(
          entry.value.toSet().length,
          entry.value.length,
          reason: entry.key,
        );
      }
    });

    test(
      'covers each smart view, a parent with children and an archived task',
      () {
        final data = buildDemoData(testToday);
        bool has(bool Function(Task) predicate) => data.tasks.any(predicate);

        expect(
          has((t) => t.dueDate == testToday && t.status == TaskStatus.open),
          isTrue,
          reason: 'Today',
        );
        expect(
          has(
            (t) =>
                t.dueDate != null &&
                t.dueDate!.compareTo(testToday) < 0 &&
                t.status == TaskStatus.open,
          ),
          isTrue,
          reason: 'Overdue',
        );
        expect(
          has(
            (t) =>
                t.dueDate != null &&
                t.dueDate!.compareTo(testToday) > 0 &&
                t.dueDate!.compareTo(testToday.addDays(7)) <= 0,
          ),
          isTrue,
          reason: 'Next 7 Days',
        );
        expect(
          has((t) => t.status == TaskStatus.archived),
          isTrue,
          reason: 'archived',
        );
        expect(
          data.tasks.any((p) => data.tasks.any((c) => c.parentId == p.id)),
          isTrue,
          reason: 'parent with children',
        );
      },
    );

    test('due dates move with the given date', () {
      final now = buildDemoData(testToday);
      final later = buildDemoData(testToday.addDays(30));

      for (final task in now.tasks.where((t) => t.dueDate != null)) {
        final moved = later.tasks.firstWhere((t) => t.id == task.id);
        expect(moved.dueDate, task.dueDate!.addDays(30), reason: task.id);
      }
    });
  });
}
