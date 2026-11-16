import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/workspace_harness.dart';

/// Owner decision (Section 5.4 item 4, approved): a Discard choice is committed
/// only after the pending create succeeds. A failed create preserves the dirty
/// draft, the selection and the pending transition.
void main() {
  group('discard commits only after a successful create', () {
    test(
      'success discards the draft, selects the new task and clears pending',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateRootTask(title: 'New', projectId: 'p2');

        await ws.resolvePending(PendingResolution.discard);

        expect(ws.state.pending, isNull);
        expect(ws.state.error, isNull);
        expect(ws.state.selectedTaskId, 'new-1');
        expect(ws.state.draft?.taskId, 'new-1');
        expect(ws.state.draft?.isDirty, isFalse);
        expect(ws.state.tasks['a']?.title, 'Alpha');
        expect(h.repository.savedTasks.map((t) => t.id), ['new-1']);
      },
    );

    test(
      'failure keeps the dirty draft, the selection and the pending create',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateRootTask(title: 'New', projectId: 'p2');
        h.repository.failNextSave = true;

        await ws.resolvePending(PendingResolution.discard);

        expect(ws.state.error, WorkspaceError.saveFailed);
        expect(ws.state.pending?.transition, isA<TransitionCreate>());
        expect(ws.state.selectedTaskId, 'a');
        expect(ws.state.draft?.title, 'Alpha 2');
        expect(ws.state.draft?.isDirty, isTrue);
        expect(ws.state.tasks.containsKey('new-1'), isFalse);
        expect(h.repository.savedTasks, isEmpty);
      },
    );

    test('retry after a failed discard commits the create once', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestCreateRootTask(title: 'New', projectId: 'p2');
      h.repository.failNextSave = true;
      await ws.resolvePending(PendingResolution.discard);

      await ws.resolvePending(PendingResolution.discard);

      expect(ws.state.pending, isNull);
      expect(ws.state.error, isNull);
      expect(ws.state.selectedTaskId, 'new-1');
      expect(ws.state.draft?.isDirty, isFalse);
      expect(h.repository.savedTasks.map((t) => t.id), ['new-1']);
    });

    test(
      'cancel after a failed discard restores the editing context',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2', notes: 'kept');
        await ws.requestCreateRootTask(title: 'New', projectId: 'p2');
        h.repository.failNextSave = true;
        await ws.resolvePending(PendingResolution.discard);

        await ws.resolvePending(PendingResolution.cancel);

        expect(ws.state.pending, isNull);
        expect(ws.state.error, isNull);
        expect(ws.state.selectedTaskId, 'a');
        expect(ws.state.draft?.title, 'Alpha 2');
        expect(ws.state.draft?.notes, 'kept');
        expect(ws.state.draft?.isDirty, isTrue);
        expect(ws.state.tasks.containsKey('new-1'), isFalse);
      },
    );

    test(
      'a failed subtask create does not expand the parent or add a child',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.toggleExpanded(
          'parent',
        ); // the user collapsed it (default is expanded)
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateSubtask(title: 'Sub', parentId: 'parent');
        h.repository.failNextSave = true;

        await ws.resolvePending(PendingResolution.discard);

        expect(ws.state.expandedTaskIds, isNot(contains('parent')));
        expect(ws.state.tasks.containsKey('new-1'), isFalse);
        expect(ws.state.draft?.title, 'Alpha 2');
      },
    );

    test('an archived parent is still refused on the discard path', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('parent');
      ws.editDraft(status: TaskStatus.archived);
      await ws.requestCreateSubtask(title: 'Sub', parentId: 'parent');

      await ws.resolvePending(PendingResolution.save);

      expect(ws.state.error, WorkspaceError.parentArchived);
      expect(ws.state.tasks.containsKey('new-1'), isFalse);
      expect(ws.state.pending?.transition, isA<TransitionCreate>());
    });
  });

  group('duplicate and concurrent transitions', () {
    test('two Discard taps commit the create exactly once', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestCreateRootTask(title: 'New', projectId: 'p2');

      await Future.wait([
        ws.resolvePending(PendingResolution.discard),
        ws.resolvePending(PendingResolution.discard),
      ]);

      expect(h.repository.savedTasks.map((t) => t.id), ['new-1']);
      expect(ws.state.pending, isNull);
      expect(ws.state.selectedTaskId, 'new-1');
    });

    test(
      'a create requested during a save is refused and nothing is persisted',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        Future<dynamic>? nested;
        h.repository.beforeSave = () {
          nested = ws.requestCreateRootTask(title: 'New', projectId: 'p2');
        };

        okValue(await ws.saveDraft());
        final refused = errValue(await nested!);

        expect(refused, WorkspaceError.operationInProgress);
        expect(h.repository.savedTasks.map((t) => t.id), ['a']);
        expect(ws.state.tasks.containsKey('new-1'), isFalse);
      },
    );

    test('a second save during a save is refused', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      Future<dynamic>? nested;
      h.repository.beforeSave = () {
        nested = ws.saveDraft();
      };

      okValue(await ws.saveDraft());
      final second = errValue(await nested!);

      expect(second, WorkspaceError.operationInProgress);
      expect(h.repository.savedTasks, hasLength(1));
    });

    test('edits are ignored while a discard commit is running', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      await ws.requestCreateRootTask(title: 'New', projectId: 'p2');
      h.repository.beforeSave = () =>
          ws.editDraft(title: 'Typed during commit');

      await ws.resolvePending(PendingResolution.discard);

      expect(ws.state.draft?.taskId, 'new-1');
      expect(ws.state.tasks['new-1']?.title, 'New');
      expect(ws.state.draft?.title, 'New');
    });
  });

  group('revert during a save', () {
    test(
      'is refused, so the saved draft is not reverted to the old base',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        h.repository.beforeSave = ws.revertDraft;

        okValue(await ws.saveDraft());

        expect(ws.state.draft?.title, 'Alpha 2');
        expect(ws.state.draft?.base.title, 'Alpha 2');
        expect(ws.state.draft?.isDirty, isFalse);
      },
    );
  });

  group('state consistency', () {
    test(
      'a failed create changes neither the task map nor the selection',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectView(SmartView.all);
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');
        await ws.requestCreateRootTask(title: 'New', projectId: 'p2');
        final before = Map.of(ws.state.tasks);
        h.repository.failNextSave = true;

        await ws.resolvePending(PendingResolution.discard);

        expect(ws.state.tasks.keys.toSet(), before.keys.toSet());
        expect(ws.state.selection, isA<SmartViewSelection>());
        expect(ws.state.selectedTaskId, 'a');
      },
    );
  });
}
