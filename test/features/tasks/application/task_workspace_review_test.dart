import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('subtask under a parent archived in the unsaved draft', () {
    test('saving the archived parent blocks the pending subtask', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('parent');
      ws.editDraft(status: TaskStatus.archived);
      await ws.requestCreateSubtask(title: 'Sub', parentId: 'parent');

      await ws.resolvePending(PendingResolution.save);

      expect(h.repository.savedTasks.single.status, TaskStatus.archived);
      expect(ws.state.tasks.containsKey('new-1'), isFalse);
      expect(ws.state.error, WorkspaceError.parentArchived);
      expect(ws.state.pending?.transition, isA<TransitionCreate>());
    });

    test('discarding the archived draft creates the subtask under the saved open parent', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('parent');
      ws.editDraft(status: TaskStatus.archived);
      await ws.requestCreateSubtask(title: 'Sub', parentId: 'parent');

      await ws.resolvePending(PendingResolution.discard);

      final child = ws.state.tasks['new-1'];
      expect(child?.parentId, 'parent');
      expect(ws.state.tasks['parent']?.status, TaskStatus.open);
      expect(h.repository.savedTasks, hasLength(1));
      expect(h.repository.savedTasks.single.id, 'new-1');
      expect(ws.state.error, isNull);
    });
  });

  group('edits made while a save is in flight', () {
    test('survive the rebase and keep the draft dirty', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      h.repository.beforeSave = () => ws.editDraft(notes: 'typed during save');

      okValue(await ws.saveDraft());

      expect(h.repository.savedTasks.single.title, 'Alpha 2');
      expect(h.repository.savedTasks.single.notes, '');
      expect(ws.state.tasks['a']?.title, 'Alpha 2');
      expect(ws.state.draft?.base.title, 'Alpha 2');
      expect(ws.state.draft?.base.notes, '');
      expect(ws.state.draft?.notes, 'typed during save');
      expect(ws.state.draft?.title, 'Alpha 2');
      expect(ws.state.draft?.isDirty, isTrue);
    });
  });
}
