import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';

import '../../../support/result_matchers.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('selection without a dirty draft', () {
    test('selecting a task loads a clean draft', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      h.workspace.requestSelectTask('a');

      final state = h.workspace.state;
      expect(state.selectedTaskId, 'a');
      expect(state.draft?.taskId, 'a');
      expect(state.draft?.isDirty, isFalse);
      expect(state.pending, isNull);
    });

    test('an unknown task id is ignored', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      h.workspace.requestSelectTask('missing');

      expect(h.workspace.state.selectedTaskId, isNull);
      expect(h.workspace.state.draft, isNull);
    });

    test(
      'a view that hides a clean selected task clears it silently',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        h.workspace.requestSelectTask('a');

        h.workspace.requestSelectView(SmartView.overdue);

        expect(h.workspace.state.selectedTaskId, isNull);
        expect(h.workspace.state.draft, isNull);
        expect(h.workspace.state.pending, isNull);
      },
    );
  });

  group('unsaved-change gate table', () {
    test('select another task while dirty: gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectTask('b');

      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.pending?.transition, isA<TransitionSelectTask>());
      expect(ws.state.draft?.title, 'Alpha 2');
    });

    test('select another task while clean: not gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');

      ws.requestSelectTask('b');

      expect(ws.state.selectedTaskId, 'b');
      expect(ws.state.pending, isNull);
    });

    test('re-selecting the drafted task while dirty: not gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectTask('a');

      expect(ws.state.pending, isNull);
      expect(ws.state.draft?.isDirty, isTrue);
    });

    test('clear selection while dirty: gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectTask(null);

      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.pending?.transition, isA<TransitionSelectTask>());
    });

    test('view change that keeps the dirty task visible: not gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectView(SmartView.today);

      expect(ws.state.pending, isNull);
      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.draft?.isDirty, isTrue);
    });

    test('view change that hides the dirty task: gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectView(SmartView.next7Days);

      expect(ws.state.pending?.transition, isA<TransitionSelectView>());
      expect(ws.state.selectedTaskId, 'a');
      expect((ws.state.selection as SmartViewSelection).view, SmartView.all);
    });

    test('project change that keeps the dirty task: not gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectProject('p1');

      expect(ws.state.pending, isNull);
      expect(ws.state.selection, isA<ProjectSelection>());
      expect(ws.state.selectedTaskId, 'a');
    });

    test('project change that hides the dirty task: gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSelectProject('p2');

      expect(ws.state.pending?.transition, isA<TransitionSelectProject>());
      expect(ws.state.selection, isA<SmartViewSelection>());
    });

    test('search that keeps the dirty task visible: not gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSearch('alp');

      expect(ws.state.pending, isNull);
      expect(ws.state.searchQuery, 'alp');
      expect(ws.state.selectedTaskId, 'a');
    });

    test('search that hides the dirty task: gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      ws.requestSearch('alp');

      ws.requestSearch('zzz');

      expect(ws.state.pending?.transition, isA<TransitionSearch>());
      expect(ws.state.searchQuery, 'alp');
    });

    test('sort change while dirty: never gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.requestSort(TaskSort.title);

      expect(ws.state.sort, TaskSort.title);
      expect(ws.state.pending, isNull);
      expect(ws.state.draft?.isDirty, isTrue);
    });

    test(
      'collapse that hides the selected row: not gated, selection kept',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.toggleExpanded('parent');
        ws.requestSelectTask('child');
        ws.editDraft(title: 'Child 2');

        ws.toggleExpanded('parent');

        expect(ws.state.pending, isNull);
        expect(ws.state.selectedTaskId, 'child');
        expect(ws.state.draft?.isDirty, isTrue);
        expect(ws.state.selectedTaskHidden, isTrue);
      },
    );

    test('create root task while dirty: gated, nothing persisted', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      final result = await ws.requestCreateRootTask(
        title: 'New',
        projectId: 'p1',
      );

      expect(okValue(result).id, 'new-1');
      expect(ws.state.pending?.transition, isA<TransitionCreate>());
      expect(ws.state.selectedTaskId, 'a');
      expect(h.repository.savedTasks, isEmpty);
    });

    test(
      'create subtask while dirty: gated and records the parent to expand',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');

        await ws.requestCreateSubtask(title: 'Sub', parentId: 'parent');

        final pending = ws.state.pending?.transition;
        expect(pending, isA<TransitionCreate>());
        expect((pending as TransitionCreate).expandParentId, 'parent');
        expect(h.repository.savedTasks, isEmpty);
      },
    );

    test('revert while dirty: not gated, draft returns to base', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      ws.revertDraft();

      expect(ws.state.pending, isNull);
      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.draft?.title, 'Alpha');
      expect(ws.state.draft?.isDirty, isFalse);
    });

    test('exit while clean: allowed immediately', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      expect(await h.workspace.requestExit(), isTrue);
      expect(h.workspace.state.pending, isNull);
    });

    test('exit while dirty: refused and gated', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');

      expect(await ws.requestExit(), isFalse);
      expect(ws.state.pending?.transition, isA<TransitionExit>());
    });
  });

  group('gate resolution', () {
    test(
      'save applies the pending selection after a successful save',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        ws.requestSelectTask('b');

        await ws.resolvePending(PendingResolution.save);

        expect(h.repository.savedTasks.single.title, 'Alpha 2');
        expect(ws.state.selectedTaskId, 'b');
        expect(ws.state.draft?.taskId, 'b');
        expect(ws.state.pending, isNull);
        expect(ws.state.error, isNull);
      },
    );

    test(
      'failed save keeps draft, pending and selection and sets saveFailed',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        ws.requestSelectTask('b');
        h.repository.failNextSave = true;

        await ws.resolvePending(PendingResolution.save);

        expect(ws.state.selectedTaskId, 'a');
        expect(ws.state.draft?.title, 'Alpha 2');
        expect(ws.state.draft?.isDirty, isTrue);
        expect(ws.state.pending?.transition, isA<TransitionSelectTask>());
        expect(ws.state.error, WorkspaceError.saveFailed);
        expect(h.repository.savedTasks, isEmpty);
      },
    );

    test('discard applies the pending selection and drops the draft', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      ws.requestSelectTask('b');

      await ws.resolvePending(PendingResolution.discard);

      expect(ws.state.selectedTaskId, 'b');
      expect(ws.state.draft?.title, 'Beta');
      expect(ws.state.pending, isNull);
      expect(h.repository.savedTasks, isEmpty);
      expect(
        (await h.repository.loadTasks()).firstWhere((t) => t.id == 'a').title,
        'Alpha',
      );
    });

    test('cancel clears only the pending transition', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      ws.requestSelectTask('b');

      await ws.resolvePending(PendingResolution.cancel);

      expect(ws.state.pending, isNull);
      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.draft?.title, 'Alpha 2');
    });

    test(
      'save then pending create persists the draft and the new task',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateRootTask(title: 'New item', projectId: 'p1');

        await ws.resolvePending(PendingResolution.save);

        expect(h.repository.savedTasks.map((t) => t.id), ['a', 'new-1']);
        expect(ws.state.selectedTaskId, 'new-1');
        expect(ws.state.tasks.containsKey('new-1'), isTrue);
        expect(ws.state.pending, isNull);
      },
    );

    test('failed save before a pending create creates nothing', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestCreateRootTask(title: 'New item', projectId: 'p1');
      h.repository.failNextSave = true;

      await ws.resolvePending(PendingResolution.save);

      expect(ws.state.tasks.containsKey('new-1'), isFalse);
      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.pending?.transition, isA<TransitionCreate>());
      expect(ws.state.error, WorkspaceError.saveFailed);
    });

    test(
      'discard with a pending create that fails to persist keeps the draft',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateRootTask(title: 'New item', projectId: 'p1');
        h.repository.failNextSave = true;

        await ws.resolvePending(PendingResolution.discard);

        expect(ws.state.tasks.containsKey('new-1'), isFalse);
        expect(ws.state.selectedTaskId, 'a');
        expect(ws.state.draft?.title, 'Alpha 2');
        expect(ws.state.pending?.transition, isA<TransitionCreate>());
        expect(ws.state.error, WorkspaceError.saveFailed);
      },
    );

    test('save on a pending exit with a successful save allows exit', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestExit();

      await ws.resolvePending(PendingResolution.save);

      expect(ws.state.exitReady, isTrue);
      expect(h.repository.savedTasks.single.title, 'Alpha 2');
    });

    test('save on a pending exit that fails does not allow exit', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestExit();
      h.repository.failNextSave = true;

      await ws.resolvePending(PendingResolution.save);

      expect(ws.state.exitReady, isFalse);
      expect(ws.state.pending?.transition, isA<TransitionExit>());
      expect(ws.state.draft?.title, 'Alpha 2');
    });

    test('discard on a pending exit allows exit and drops the draft', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestExit();

      await ws.resolvePending(PendingResolution.discard);

      expect(ws.state.exitReady, isTrue);
      expect(ws.state.draft, isNull);
      expect(h.repository.savedTasks, isEmpty);
    });
  });
}
