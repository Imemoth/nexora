import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

/// Incoming changes (a synchronization pulled something) must show up without
/// any navigation, and must never overwrite unsaved edits.
void main() {
  group('incoming creation, update and deletion', () {
    test('a created task appears in the list and in the counts', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final before = h.workspace.state.countFor(
        const SmartViewSelection(SmartView.all),
      );
      await h.repository.saveTask(
        makeTask(id: 'z', title: 'Pulled', dueDate: testToday),
      );

      expect(await h.workspace.refresh(), isTrue);

      final state = h.workspace.state;
      expect(state.tasks.containsKey('z'), isTrue);
      expect(state.visibleRows.map((r) => r.task.id), contains('z'));
      expect(
        state.countFor(const SmartViewSelection(SmartView.all)),
        before + 1,
      );
      expect(
        state.countFor(const SmartViewSelection(SmartView.today)),
        greaterThan(0),
      );
    });

    test('an update changes the list row without navigation', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      await h.repository.saveTask(
        h.workspace.state.tasks['c']!.copyWith(title: 'Renamed elsewhere'),
      );

      await h.workspace.refresh();

      expect(h.workspace.state.tasks['c']!.title, 'Renamed elsewhere');
    });

    test('a deleted task leaves the list', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      await h.repository.softDeleteTaskTree('c');

      await h.workspace.refresh();

      expect(h.workspace.state.tasks.containsKey('c'), isFalse);
    });

    test(
      'a project change updates the counts of the Dashboard source',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        const p1 = ProjectSelection('p1');
        final before = h.workspace.state.countFor(p1);
        await h.repository.saveTask(makeTask(id: 'z', title: 'New in Home'));

        await h.workspace.refresh();

        expect(h.workspace.state.countFor(p1), before + 1);
      },
    );
  });

  group('the selected task', () {
    test(
      'a clean selected task follows an incoming update (the reported bug)',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        h.workspace.requestSelectTask('a'); // viewing it, nothing edited
        expect(h.workspace.state.draft!.isDirty, isFalse);
        await h.repository.saveTask(
          h.workspace.state.tasks['a']!.copyWith(
            title: 'Alpha (remote)',
            status: TaskStatus.inProgress,
          ),
        );

        expect(await h.workspace.refresh(), isTrue);

        final state = h.workspace.state;
        expect(state.selectedTaskId, 'a'); // selection kept
        expect(state.draft!.title, 'Alpha (remote)'); // details follow
        expect(state.draft!.status, TaskStatus.inProgress);
        expect(state.draft!.isDirty, isFalse);
        expect(state.incoming, isNull);
      },
    );

    test('a clean selected task that was deleted is deselected', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      await h.repository.softDeleteTaskTree('a');

      await h.workspace.refresh();

      expect(h.workspace.state.selectedTaskId, isNull);
      expect(h.workspace.state.draft, isNull);
    });

    test(
      'the selection of another task is untouched by an unrelated change',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        h.workspace.requestSelectTask('a');
        await h.repository.saveTask(makeTask(id: 'z', title: 'Other'));

        await h.workspace.refresh();

        expect(h.workspace.state.selectedTaskId, 'a');
        expect(h.workspace.state.draft!.isDirty, isFalse);
      },
    );
  });

  group('an incoming change while local edits are unsaved', () {
    test(
      'keeps the edited field, takes the untouched ones, and says so',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        h.workspace.requestSelectTask('a');
        h.workspace.editDraft(title: 'My title');
        await h.repository.saveTask(
          h.workspace.state.tasks['a']!.copyWith(
            notes: 'Remote notes',
            status: TaskStatus.review,
          ),
        );

        expect(await h.workspace.refresh(), isTrue);

        final state = h.workspace.state;
        expect(state.draft!.title, 'My title'); // never overwritten
        expect(state.draft!.notes, 'Remote notes'); // untouched field follows
        expect(state.draft!.status, TaskStatus.review);
        expect(state.draft!.isDirty, isTrue);
        expect(state.incoming!.kind, IncomingKind.updated);
        expect(state.incoming!.overlap, isEmpty);
        // The list shows the stored task; the draft is still the user's.
        expect(state.tasks['a']!.title, 'Alpha');
      },
    );

    test('an overlapping edit is kept and reported, never replaced', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Mine');
      await h.repository.saveTask(
        h.workspace.state.tasks['a']!.copyWith(title: 'Theirs'),
      );

      await h.workspace.refresh();

      expect(h.workspace.state.draft!.title, 'Mine');
      expect(h.workspace.state.incoming!.overlap, {'title'});
      // Revert loads the incoming version and clears the notice.
      h.workspace.revertDraft();
      expect(h.workspace.state.draft!.title, 'Theirs');
      expect(h.workspace.state.draft!.isDirty, isFalse);
      expect(h.workspace.state.incoming, isNull);
    });

    test('saving after an incoming change writes the merged draft', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Mine');
      await h.repository.saveTask(
        h.workspace.state.tasks['a']!.copyWith(notes: 'Remote notes'),
      );
      await h.workspace.refresh();

      final saved = await h.workspace.saveDraft();

      expect(saved, isA<Ok<void, WorkspaceError>>());
      final stored = h.repository.savedTasks.last;
      expect(stored.title, 'Mine');
      expect(stored.notes, 'Remote notes'); // the incoming change survived
      expect(h.workspace.state.incoming, isNull);
    });

    test(
      'a deletion keeps the edits, refuses Save, and Revert leaves',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        h.workspace.requestSelectTask('a');
        h.workspace.editDraft(title: 'Unsaved work');
        await h.repository.softDeleteTaskTree('a');

        await h.workspace.refresh();

        var state = h.workspace.state;
        expect(state.draft!.title, 'Unsaved work'); // not discarded
        expect(state.selectedTaskId, 'a');
        expect(state.incoming!.kind, IncomingKind.deleted);

        final saved = await h.workspace.saveDraft();
        expect(saved, isA<Err<void, WorkspaceError>>());
        expect(h.workspace.state.error, WorkspaceError.taskDeletedElsewhere);

        h.workspace.revertDraft();
        state = h.workspace.state;
        expect(state.draft, isNull);
        expect(state.selectedTaskId, isNull);
        expect(state.incoming, isNull);
      },
    );

    test('selecting another task ends the notice', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Mine');
      await h.repository.saveTask(
        h.workspace.state.tasks['a']!.copyWith(notes: 'x'),
      );
      await h.workspace.refresh();
      expect(h.workspace.state.incoming, isNotNull);

      h.workspace.revertDraft();
      h.workspace.requestSelectTask('b');

      expect(h.workspace.state.incoming, isNull);
    });

    test(
      'a due time edited locally survives an incoming date change',
      () async {
        final h = await loadedHarness(tasks: sampleTasks());
        h.workspace.requestSelectTask('a'); // due today
        h.workspace.editDraft(dueTime: const DueTime(14, 30));
        await h.repository.saveTask(
          h.workspace.state.tasks['a']!.copyWith(
            dueDate: const CalendarDate(2026, 12, 1),
          ),
        );

        await h.workspace.refresh();

        final draft = h.workspace.state.draft!;
        expect(draft.dueDate, const CalendarDate(2026, 12, 1));
        expect(draft.dueTime, const DueTime(14, 30));
      },
    );
  });

  group('refresh while busy or unreadable', () {
    test('a refresh that arrives during a save runs afterwards', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Mine');
      h.repository.beforeSave = () {
        // The pull lands while the save is in flight.
        h.repository.beforeSave = null;
        h.workspace.refresh();
      };
      final remote = makeTask(id: 'z', title: 'Pulled meanwhile');
      await h.repository.saveTask(remote);

      await h.workspace.saveDraft();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(h.workspace.state.tasks.containsKey('z'), isTrue);
      expect(h.workspace.state.draft!.title, 'Mine');
    });

    test('an unreadable store changes nothing and reports false', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      final before = h.workspace.state;
      h.repository.failNextLoad = true;

      expect(await h.workspace.refresh(), isFalse);

      expect(h.workspace.state.tasks, before.tasks);
      expect(h.workspace.state.selectedTaskId, 'a');
    });

    test('a project that disappeared falls back to All', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectProject('p2');
      await h.repository.softDeleteProjectTree('p2');

      await h.workspace.refresh();

      expect(
        h.workspace.state.selection,
        isA<SmartViewSelection>().having((s) => s.view, 'view', SmartView.all),
      );
    });
  });
}
