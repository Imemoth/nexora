import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

import '../../../support/result_matchers.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('friendly dates', () {
    const today = CalendarDate(2026, 11, 12); // Thursday

    test('today and tomorrow are words', () {
      expect(
        AppStrings.friendlyDue(today, today, closed: false),
        AppStrings.dueToday,
      );
      expect(
        AppStrings.friendlyDue(today.addDays(1), today, closed: false),
        AppStrings.dueTomorrow,
      );
    });

    test('another day reads weekday, day and month', () {
      expect(
        AppStrings.friendlyDue(
          const CalendarDate(2026, 11, 16),
          today,
          closed: false,
        ),
        'Mon 16 Nov',
      );
    });

    test('an open task in the past is overdue', () {
      expect(
        AppStrings.friendlyDue(
          const CalendarDate(2026, 11, 10),
          today,
          closed: false,
        ),
        'Overdue · Tue 10 Nov',
      );
    });

    test('a done task with a past date is not overdue', () {
      expect(
        AppStrings.friendlyDue(
          const CalendarDate(2026, 11, 10),
          today,
          closed: true,
        ),
        'Tue 10 Nov',
      );
    });
  });

  group('status filter', () {
    test('filters rows by status and never opens the gate or touches the draft', () async {
      final h = await loadedHarness(
        tasks: [
          makeTask(id: 'a', title: 'A', status: TaskStatus.open),
          makeTask(id: 'b', title: 'B', status: TaskStatus.done),
          makeTask(id: 'c', title: 'C', status: TaskStatus.review),
        ],
      );
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'A edited');
      expect(ws.state.draft!.isDirty, isTrue);

      ws.requestStatusFilter(TaskStatus.done);
      expect(ws.state.pending, isNull);
      expect(ws.state.draft!.title, 'A edited');
      expect(ws.state.visibleRows.map((r) => r.task.id), ['b']);
      // A selected task the filter hides stays selected and is reported hidden.
      expect(ws.state.selectedTaskId, 'a');
      expect(ws.state.selectedTaskHidden, isTrue);

      ws.requestStatusFilter(null);
      expect(ws.state.visibleRows, hasLength(3));
      expect(ws.state.selectedTaskHidden, isFalse);
    });

    test('chip counts ignore the filter itself', () async {
      final h = await loadedHarness(
        tasks: [
          makeTask(id: 'a', status: TaskStatus.open),
          makeTask(id: 'b', status: TaskStatus.open),
          makeTask(id: 'c', status: TaskStatus.done),
        ],
      );
      h.workspace.requestStatusFilter(TaskStatus.done);
      expect(h.workspace.state.statusCount(null), 3);
      expect(h.workspace.state.statusCount(TaskStatus.open), 2);
      expect(h.workspace.state.statusCount(TaskStatus.done), 1);
      expect(h.workspace.state.doneCount, 1);
    });

    test('creating a task the filter would hide clears the filter', () async {
      final h = await loadedHarness(
        tasks: [makeTask(id: 'a', status: TaskStatus.done)],
      );
      final ws = h.workspace;
      ws.requestSelectProject('p1');
      ws.requestStatusFilter(TaskStatus.done);
      final created = await ws.requestCreateRootTask(
        title: 'New one',
        projectId: 'p1',
      );
      expect(created, isA<Ok<dynamic, WorkspaceError>>());
      expect(ws.state.statusFilter, isNull);
      expect(
        ws.state.visibleRows.any((r) => r.task.title == 'New one'),
        isTrue,
      );
    });
  });

  group('dashboard and sign-out go through the gate', () {
    test('the dashboard is a navigation target with no rows', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectDashboard();
      expect(h.workspace.state.selection, isA<DashboardSelection>());
      expect(h.workspace.state.visibleRows, isEmpty);
    });

    test('entering the dashboard with a dirty draft opens the gate', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'changed');
      ws.requestSelectDashboard();
      expect(ws.state.pending?.transition, isA<TransitionSelectDashboard>());
      expect(ws.state.selection, isNot(isA<DashboardSelection>()));
      await ws.resolvePending(PendingResolution.discard);
      expect(ws.state.selection, isA<DashboardSelection>());
      expect(ws.state.selectedTaskId, isNull);
    });

    test('sign-out with a clean draft is allowed at once', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      expect(await h.workspace.requestSignOut(), isTrue);
    });

    test(
      'sign-out with a dirty draft opens the gate; Save then releases it',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        final ws = h.workspace;
        ws.requestSelectTask('a');
        ws.editDraft(title: 'kept');
        expect(await ws.requestSignOut(), isFalse);
        expect(ws.state.pending?.transition, isA<TransitionSignOut>());
        expect(ws.state.signOutReady, isFalse);

        await ws.resolvePending(PendingResolution.save);
        expect(ws.state.signOutReady, isTrue);
        expect(h.repository.savedTasks.last.title, 'kept');
        ws.clearSignOutReady();
        expect(ws.state.signOutReady, isFalse);
      },
    );

    test('Cancel keeps the account and the draft', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final ws = h.workspace;
      ws.requestSelectTask('a');
      ws.editDraft(title: 'kept');
      await ws.requestSignOut();
      await ws.resolvePending(PendingResolution.cancel);
      expect(ws.state.signOutReady, isFalse);
      expect(ws.state.draft!.title, 'kept');
    });
  });

  group('delete', () {
    List<dynamic> tree() => [
      makeTask(id: 'root', title: 'Root'),
      makeTask(id: 'kid', parentId: 'root', title: 'Kid'),
      makeTask(id: 'grandkid', parentId: 'kid', title: 'Grandkid'),
      makeTask(id: 'other', title: 'Other'),
      makeTask(id: 'w', projectId: 'p2', title: 'Work task'),
    ];

    test(
      'deleting a task removes its whole subtree in one repository call',
      () async {
        final h = await loadedHarness(tasks: tree().cast());
        final result = await h.workspace.deleteTask('root');
        expect(result, isA<Ok<dynamic, WorkspaceError>>());
        expect(h.workspace.state.tasks.keys.toSet(), {'other', 'w'});
        final stored = await h.repository.loadTasks();
        expect(stored.map((t) => t.id).toSet(), {'other', 'w'});
      },
    );

    test('the subtree is reported leaf first', () async {
      final h = await loadedHarness(tasks: tree().cast());
      expect(h.workspace.subtreeOf('root'), ['grandkid', 'kid', 'root']);
    });

    test('deleting the selected task drops selection and draft', () async {
      final h = await loadedHarness(tasks: tree().cast());
      final ws = h.workspace;
      ws.requestSelectTask('kid');
      await ws.deleteTask('root');
      expect(ws.state.selectedTaskId, isNull);
      expect(ws.state.draft, isNull);
    });

    test('another selected task keeps its selection and draft', () async {
      final h = await loadedHarness(tasks: tree().cast());
      final ws = h.workspace;
      ws.requestSelectTask('other');
      ws.editDraft(title: 'still editing');
      await ws.deleteTask('root');
      expect(ws.state.selectedTaskId, 'other');
      expect(ws.state.draft!.title, 'still editing');
    });

    test('a failed delete changes nothing', () async {
      final h = await loadedHarness(tasks: tree().cast());
      h.repository.failNextDelete = true;
      final result = await h.workspace.deleteTask('root');
      expect(result, isA<Err<dynamic, WorkspaceError>>());
      expect(errValue(result), WorkspaceError.deleteFailed);
      expect(h.workspace.state.tasks, hasLength(5));
      expect(await h.repository.loadTasks(), hasLength(5));
    });

    test('delete is refused while the gate is open', () async {
      final h = await loadedHarness(tasks: tree().cast());
      final ws = h.workspace;
      ws.requestSelectTask('other');
      ws.editDraft(title: 'x');
      ws.requestSelectTask('w'); // opens the gate
      expect(ws.state.pending, isNotNull);
      final result = await ws.deleteTask('root');
      expect(errValue(result), WorkspaceError.unsavedChangesPending);
      expect(ws.state.tasks, hasLength(5));
    });

    test('deleting a project removes it with all its tasks', () async {
      final h = await loadedHarness(tasks: tree().cast());
      final ws = h.workspace;
      ws.requestSelectProject('p1');
      final result = await ws.deleteProject('p1');
      expect(result, isA<Ok<dynamic, WorkspaceError>>());
      expect(ws.state.projects.map((p) => p.id), ['p2']);
      expect(ws.state.tasks.keys, ['w']);
      // The open project moves to a remaining one.
      expect((ws.state.selection as ProjectSelection).projectId, 'p2');
    });

    test('the last project cannot be deleted', () async {
      final h = await loadedHarness(
        tasks: [makeTask(id: 'a')],
        projects: [testProjects.first],
      );
      final result = await h.workspace.deleteProject('p1');
      expect(errValue(result), WorkspaceError.lastProject);
      expect(h.workspace.state.projects, hasLength(1));
    });

    test(
      'a project with unsaved edits inside is not deleted silently',
      () async {
        final h = await loadedHarness(tasks: tree().cast());
        final ws = h.workspace;
        ws.requestSelectTask('other');
        ws.editDraft(title: 'unsaved');
        final result = await ws.deleteProject('p1');
        expect(errValue(result), WorkspaceError.unsavedChangesPending);
        expect(ws.state.projects, hasLength(2));
      },
    );
  });
}
