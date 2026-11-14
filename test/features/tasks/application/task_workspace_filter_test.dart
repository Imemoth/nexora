import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  Future<Harness> mixed() => loadedHarness(
    tasks: [
      makeTask(id: 'o1', title: 'Open one'),
      makeTask(id: 'o2', title: 'Open two', position: 1),
      makeTask(
        id: 'd1',
        title: 'Done one',
        status: TaskStatus.done,
        position: 2,
      ),
      makeTask(
        id: 'p1',
        title: 'Working',
        status: TaskStatus.inProgress,
        position: 3,
      ),
    ],
  );

  group('status filter', () {
    test('lists only tasks with that status', () async {
      final h = await mixed();

      h.workspace.requestStatusFilter(TaskStatus.done);

      expect(h.workspace.state.visibleRows.map((r) => r.task.id), ['d1']);
      expect(h.workspace.state.resultCount, 1);
    });

    test('null shows every status again', () async {
      final h = await mixed();
      h.workspace.requestStatusFilter(TaskStatus.done);

      h.workspace.requestStatusFilter(null);

      expect(h.workspace.state.statusFilter, isNull);
      expect(h.workspace.state.visibleRows.length, 4);
    });

    test('chip counts ignore the filter itself', () async {
      final h = await mixed();
      h.workspace.requestStatusFilter(TaskStatus.done);

      expect(h.workspace.state.countForStatus(null), 4);
      expect(h.workspace.state.countForStatus(TaskStatus.open), 2);
      expect(h.workspace.state.countForStatus(TaskStatus.done), 1);
    });

    test('is never gated and keeps a dirty draft', () async {
      final h = await mixed();
      h.workspace.requestSelectTask('o1');
      h.workspace.editDraft(title: 'Edited');

      h.workspace.requestStatusFilter(TaskStatus.done);

      expect(h.workspace.state.pending, isNull);
      expect(h.workspace.state.selectedTaskId, 'o1');
      expect(h.workspace.state.draft?.title, 'Edited');
      expect(h.workspace.state.selectedTaskHidden, isTrue);
    });

    test('creating a task the filter would hide clears the filter', () async {
      final h = await mixed();
      h.workspace.requestStatusFilter(TaskStatus.done);

      final result = await h.workspace.requestCreateRootTask(
        title: 'Fresh',
        projectId: 'p1',
      );

      final created = okValue(result);
      expect(h.workspace.state.statusFilter, isNull);
      expect(
        h.workspace.state.visibleRows.any((r) => r.task.id == created.id),
        isTrue,
      );
    });
  });
}
