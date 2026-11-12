import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('load', () {
    test('populates projects and tasks and finishes loading', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      expect(h.workspace.state.projects.map((p) => p.id), ['p1', 'p2']);
      expect(h.workspace.state.tasks.length, sampleTasks().length);
      expect(h.workspace.state.loading, isFalse);
      expect(h.workspace.state.error, isNull);
    });

    test(
      'a load failure sets loadFailed and leaves the workspace empty',
      () async {
        final h = await loadedHarness(tasks: sampleTasks(), failLoad: true);

        expect(h.workspace.state.error, WorkspaceError.loadFailed);
        expect(h.workspace.state.tasks, isEmpty);
        expect(h.workspace.state.projects, isEmpty);
        expect(h.workspace.state.loading, isFalse);
      },
    );

    test('states stream emits after changes', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final emitted = <Object?>[];
      final subscription = h.workspace.states.listen(
        (state) => emitted.add(state.selectedTaskId),
      );

      h.workspace.requestSelectTask('a');
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(emitted, ['a']);
    });
  });

  group('draft editing', () {
    test('edits change the draft and mark it dirty', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');

      h.workspace.editDraft(
        title: 'Alpha 2',
        status: TaskStatus.inProgress,
        priority: TaskPriority.high,
        notes: 'Some notes',
      );

      final draft = h.workspace.state.draft!;
      expect(draft.title, 'Alpha 2');
      expect(draft.status, TaskStatus.inProgress);
      expect(draft.priority, TaskPriority.high);
      expect(draft.notes, 'Some notes');
      expect(draft.isDirty, isTrue);
      expect(h.repository.savedTasks, isEmpty);
    });

    test('clearDueDate removes the due date', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');

      h.workspace.editDraft(clearDueDate: true);

      expect(h.workspace.state.draft?.dueDate, isNull);
      expect(h.workspace.state.draft?.isDirty, isTrue);
    });

    test('setting a due date stores the date-only value', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('c');

      h.workspace.editDraft(dueDate: const CalendarDate(2026, 12, 1));

      expect(h.workspace.state.draft?.dueDate?.toIsoString(), '2026-12-01');
    });

    test('a clean edit that restores the base values is not dirty', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');

      h.workspace.editDraft(title: 'Alpha 2');
      h.workspace.editDraft(title: 'Alpha');

      expect(h.workspace.state.draft?.isDirty, isFalse);
    });

    test('revert restores the base values', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Alpha 2', priority: TaskPriority.low);

      h.workspace.revertDraft();

      expect(h.workspace.state.draft?.title, 'Alpha');
      expect(h.workspace.state.draft?.priority, TaskPriority.none);
      expect(h.workspace.state.draft?.isDirty, isFalse);
    });
  });

  group('saveDraft', () {
    test(
      'a blank title is rejected, the draft is kept and nothing is saved',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: '   ');

        final result = await ws.saveDraft();

        expect(errValue(result), WorkspaceError.titleRequired);
        expect(ws.state.error, WorkspaceError.titleRequired);
        expect(ws.state.draft?.title, '   ');
        expect(h.repository.savedTasks, isEmpty);
      },
    );

    test('a title over 200 characters is rejected', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'x' * 201);

      expect(errValue(await ws.saveDraft()), WorkspaceError.titleTooLong);
      expect(h.repository.savedTasks, isEmpty);
    });

    test('success stores the trimmed title and rebases the draft', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: '  Alpha 2  ', status: TaskStatus.done);

      okValue(await ws.saveDraft());

      expect(h.repository.savedTasks.single.title, 'Alpha 2');
      expect(h.repository.savedTasks.single.status, TaskStatus.done);
      expect(ws.state.tasks['a']?.title, 'Alpha 2');
      expect(ws.state.draft?.title, 'Alpha 2');
      expect(ws.state.draft?.isDirty, isFalse);
      expect(ws.state.error, isNull);
    });

    test('a saved cleared due date is removed from the stored task', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(clearDueDate: true);

      okValue(await ws.saveDraft());

      expect(h.repository.savedTasks.single.dueDate, isNull);
    });

    test('a failed save keeps the draft and the base unchanged', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      h.repository.failNextSave = true;

      final result = await ws.saveDraft();

      expect(errValue(result), WorkspaceError.saveFailed);
      expect(ws.state.draft?.title, 'Alpha 2');
      expect(ws.state.draft?.isDirty, isTrue);
      expect(ws.state.tasks['a']?.title, 'Alpha');
      expect(ws.state.error, WorkspaceError.saveFailed);
    });

    test('saving a clean draft is a no-op', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');

      okValue(await h.workspace.saveDraft());

      expect(h.repository.savedTasks, isEmpty);
    });

    test('a saved edit moves the row to its new sorted place', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSort(TaskSort.title);
      ws.requestSelectTask('c');
      ws.editDraft(title: 'Aardvark');

      okValue(await ws.saveDraft());

      expect(ws.state.visibleRows.first.task.id, 'c');
    });
  });

  group('creation', () {
    test('root task is appended to its project and selected', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;

      final created = okValue(
        await ws.requestCreateRootTask(title: '  Plan trip  ', projectId: 'p2'),
      );

      expect(created.id, 'new-1');
      expect(created.title, 'Plan trip');
      expect(created.projectId, 'p2');
      expect(created.parentId, isNull);
      expect(created.position, 1);
      expect(created.status, TaskStatus.open);
      expect(created.notes, '');
      expect(ws.state.selectedTaskId, 'new-1');
      expect(ws.state.draft?.isDirty, isFalse);
      expect(h.repository.savedTasks.single.id, 'new-1');
    });

    test(
      'an invalid root title is rejected with no state change, even when dirty',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'Alpha 2');

        final result = await ws.requestCreateRootTask(
          title: '  ',
          projectId: 'p1',
        );

        expect(errValue(result), WorkspaceError.titleRequired);
        expect(ws.state.pending, isNull);
        expect(ws.state.draft?.title, 'Alpha 2');
        expect(h.repository.savedTasks, isEmpty);
      },
    );

    test('an unknown project is rejected', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      final result = await h.workspace.requestCreateRootTask(
        title: 'New',
        projectId: 'nope',
      );

      expect(errValue(result), WorkspaceError.unknownProject);
      expect(h.workspace.state.tasks.containsKey('new-1'), isFalse);
    });

    test(
      'a failed root persist returns saveFailed and changes nothing',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        h.repository.failNextSave = true;

        final result = await ws.requestCreateRootTask(
          title: 'New',
          projectId: 'p1',
        );

        expect(errValue(result), WorkspaceError.saveFailed);
        expect(ws.state.tasks.containsKey('new-1'), isFalse);
        expect(ws.state.selectedTaskId, 'a');
      },
    );

    test('creation is refused while a gate is open', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'Alpha 2');
      ws.requestSelectTask('b');

      final result = await ws.requestCreateRootTask(
        title: 'New',
        projectId: 'p1',
      );

      expect(errValue(result), WorkspaceError.unsavedChangesPending);
      expect(ws.state.pending?.transition, isNot(isA<TransitionCreate>()));
    });

    test(
      'subtask inherits the project and is appended after siblings',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;

        final child = okValue(
          await ws.requestCreateSubtask(title: 'Pack bags', parentId: 'parent'),
        );

        expect(child.parentId, 'parent');
        expect(child.projectId, 'p1');
        expect(child.position, 1);
        expect(ws.state.expandedTaskIds, contains('parent'));
        expect(ws.state.selectedTaskId, child.id);
        expect(ws.state.tasks['parent']?.status, TaskStatus.open);
      },
    );

    test(
      'three subtasks under one parent get positions 0, 1, 2 in creation order',
      () async {
        final h = await loadedHarness(
          tasks: [makeTask(id: 'lonely', title: 'Lonely', projectId: 'p2')],
        );
        final ws = h.workspace;

        await ws.requestCreateSubtask(title: 'First', parentId: 'lonely');
        await ws.requestCreateSubtask(title: 'Second', parentId: 'lonely');
        await ws.requestCreateSubtask(title: 'Third', parentId: 'lonely');

        final children =
            ws.state.tasks.values.where((t) => t.parentId == 'lonely').toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        expect(children.map((t) => t.title), ['First', 'Second', 'Third']);
        expect(children.map((t) => t.position), [0, 1, 2]);
      },
    );

    test('a subtask under an archived parent is rejected', () async {
      final h = await loadedHarness(
        tasks: [makeTask(id: 'old', status: TaskStatus.archived)],
      );

      final result = await h.workspace.requestCreateSubtask(
        title: 'Sub',
        parentId: 'old',
      );

      expect(errValue(result), WorkspaceError.parentArchived);
      expect(h.repository.savedTasks, isEmpty);
    });

    test('a subtask under an unknown parent is rejected', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      final result = await h.workspace.requestCreateSubtask(
        title: 'Sub',
        parentId: 'ghost',
      );

      expect(errValue(result), WorkspaceError.unknownParent);
    });

    test('creating a subtask never changes a done parent', () async {
      final h = await loadedHarness(
        tasks: [makeTask(id: 'finished', status: TaskStatus.done)],
      );

      okValue(
        await h.workspace.requestCreateSubtask(
          title: 'Extra',
          parentId: 'finished',
        ),
      );

      expect(h.workspace.state.tasks['finished']?.status, TaskStatus.done);
    });

    test('closing every child does not change the parent status', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('child');
      ws.editDraft(status: TaskStatus.done);

      okValue(await ws.saveDraft());

      expect(ws.state.tasks['parent']?.status, TaskStatus.open);
    });
  });

  group('derived view state', () {
    test('visible rows follow the chosen sort', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectProject('p1');

      ws.requestSort(TaskSort.title);

      expect(ws.state.visibleRows.map((r) => r.task.id), ['a', 'b', 'parent']);
    });

    test('search matches notes and narrows the rows', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;

      ws.requestSearch('offers');

      expect(ws.state.visibleRows.map((r) => r.task.id), ['b']);
    });

    test('a search with no matches gives no rows', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      h.workspace.requestSearch('zzz');

      expect(h.workspace.state.visibleRows, isEmpty);
    });

    test(
      'expanded parents show their children with depth and completion',
      () async {
        final h = await loadedHarness(
          tasks: [
            makeTask(id: 'parent', title: 'Parent'),
            makeTask(id: 'c1', parentId: 'parent', status: TaskStatus.done),
            makeTask(id: 'c2', parentId: 'parent'),
          ],
        );
        final ws = h.workspace;
        ws.toggleExpanded('parent');

        final rows = ws.state.visibleRows;

        expect(rows.map((r) => r.task.id), ['parent', 'c1', 'c2']);
        expect(rows[0].hasChildren, isTrue);
        expect(rows[0].expanded, isTrue);
        expect(rows[0].completion?.total, 2);
        expect(rows[0].completion?.done, 1);
        expect(rows[1].depth, 1);
        expect(rows[1].completion, isNull);
      },
    );

    test('counts ignore search and match the selection', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSearch('zzz');

      expect(ws.state.countFor(const ProjectSelection('p1')), 4);
      expect(ws.state.countFor(const ProjectSelection('p2')), 1);
      expect(ws.state.countFor(const SmartViewSelection(SmartView.today)), 1);
      expect(ws.state.countFor(const SmartViewSelection(SmartView.all)), 5);
    });

    test('result count includes hidden children and applies search', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;

      expect(ws.state.resultCount, 5);
      ws.requestSearch('offers');
      expect(ws.state.resultCount, 1);
      ws.requestSearch('');
      ws.requestSelectProject('p2');
      expect(ws.state.resultCount, 1);
    });
  });
}
