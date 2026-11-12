import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('a created task is revealed in the list', () {
    test('an undated root task created in Today selects its project', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectView(SmartView.today);

      okValue(await ws.requestCreateRootTask(title: 'New', projectId: 'p2'));

      expect(ws.state.selection, isA<ProjectSelection>());
      expect((ws.state.selection as ProjectSelection).projectId, 'p2');
      expect(ws.state.selectedTaskId, 'new-1');
      expect(ws.state.selectedTaskHidden, isFalse);
      expect(ws.state.visibleRows.map((r) => r.task.id), contains('new-1'));
    });

    test('a created task is never given a due date', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectView(SmartView.overdue);

      final created = okValue(
        await ws.requestCreateRootTask(title: 'New', projectId: 'p1'),
      );

      expect(created.dueDate, isNull);
      expect(ws.state.tasks['new-1']?.dueDate, isNull);
    });

    test('a search that hides the new task is cleared', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSearch('alpha');

      okValue(await ws.requestCreateRootTask(title: 'Zeta', projectId: 'p1'));

      expect(ws.state.searchQuery, '');
      expect(ws.state.selectedTaskHidden, isFalse);
      expect(ws.state.visibleRows.map((r) => r.task.id), contains('new-1'));
    });

    test('a visible new task keeps the current view and search', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSearch('ze');

      okValue(await ws.requestCreateRootTask(title: 'Zeta', projectId: 'p1'));

      expect((ws.state.selection as SmartViewSelection).view, SmartView.all);
      expect(ws.state.searchQuery, 'ze');
      expect(ws.state.selectedTaskId, 'new-1');
    });

    test(
      'a subtask of a parent hidden by the view reveals the child',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectView(SmartView.today);

        okValue(await ws.requestCreateSubtask(title: 'Sub', parentId: 'a'));

        expect(ws.state.selection, isA<ProjectSelection>());
        expect(ws.state.selectedTaskId, 'new-1');
        expect(ws.state.tasks['a']?.status, TaskStatus.open);
      },
    );

    test(
      'a reveal after a gated save keeps the draft that was saved',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectView(SmartView.today);
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateRootTask(title: 'New', projectId: 'p2');

        await ws.resolvePending(PendingResolution.save);

        expect(h.repository.savedTasks.map((t) => t.id), ['a', 'new-1']);
        expect(ws.state.pending, isNull);
        expect((ws.state.selection as ProjectSelection).projectId, 'p2');
        expect(ws.state.selectedTaskId, 'new-1');
      },
    );
  });

  group('exit requests', () {
    test(
      'repeated exit requests while dirty keep one exit gate open',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');

        expect(await ws.requestExit(), isFalse);
        expect(await ws.requestExit(), isFalse);

        expect(ws.state.pending?.transition, isA<TransitionExit>());
        expect(h.repository.savedTasks, isEmpty);
        expect(ws.state.exitReady, isFalse);
      },
    );

    test(
      'cancelling after repeated requests leaves the draft untouched',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestExit();
        await ws.requestExit();

        await ws.resolvePending(PendingResolution.cancel);

        expect(ws.state.pending, isNull);
        expect(ws.state.exitReady, isFalse);
        expect(ws.state.draft?.title, 'Alpha 2');
      },
    );
  });
}
