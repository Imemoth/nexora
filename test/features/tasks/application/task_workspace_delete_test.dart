import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('delete task', () {
    test('removes the task and its subtasks, children first', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      final result = await h.workspace.requestDeleteTask('parent');

      okValue(result);
      expect(h.workspace.state.tasks.containsKey('parent'), isFalse);
      expect(h.workspace.state.tasks.containsKey('child'), isFalse);
      expect(h.repository.deletedIds, ['child', 'parent']);
    });

    test('keeps unrelated tasks', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      await h.workspace.requestDeleteTask('a');

      expect(h.workspace.state.tasks.containsKey('b'), isTrue);
      expect(h.workspace.state.tasks.containsKey('a'), isFalse);
    });

    test('clears the selection and draft of the deleted task', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');

      await h.workspace.requestDeleteTask('a');

      expect(h.workspace.state.selectedTaskId, isNull);
      expect(h.workspace.state.draft, isNull);
    });

    test('a dirty draft inside the deleted tree is dropped with it', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('child');
      h.workspace.editDraft(title: 'Edited');

      final result = await h.workspace.requestDeleteTask('parent');

      okValue(result);
      expect(h.workspace.state.draft, isNull);
    });

    test('a dirty draft of another task blocks the delete', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Edited');

      final result = await h.workspace.requestDeleteTask('b');

      expect(errValue(result), WorkspaceError.unsavedChangesPending);
      expect(h.workspace.state.tasks.containsKey('b'), isTrue);
      expect(h.workspace.state.draft?.title, 'Edited');
      expect(h.repository.deletedIds, isEmpty);
    });

    test('a failed delete changes nothing and reports deleteFailed', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.repository.failNextDelete = true;

      final result = await h.workspace.requestDeleteTask('a');

      expect(errValue(result), WorkspaceError.deleteFailed);
      expect(h.workspace.state.tasks.containsKey('a'), isTrue);
      expect(h.workspace.state.error, WorkspaceError.deleteFailed);
    });

    test('an unknown task is reported', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      final result = await h.workspace.requestDeleteTask('missing');

      expect(errValue(result), WorkspaceError.unknownTask);
    });

    test('counts the task and its descendants', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      expect(h.workspace.deletionCountForTask('parent'), 2);
      expect(h.workspace.deletionCountForTask('a'), 1);
      expect(h.workspace.deletionCountForTask('missing'), 0);
    });
  });

  group('delete project', () {
    test('removes the project and every task in it, leaf-first', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      final result = await h.workspace.requestDeleteProject('p1');

      okValue(result);
      expect(h.workspace.state.projects.map((p) => p.id), ['p2']);
      expect(h.workspace.state.tasks.keys, ['c']);
      expect(h.repository.deletedIds.last, 'p1');
      expect(
        h.repository.deletedIds.indexOf('child'),
        lessThan(h.repository.deletedIds.indexOf('parent')),
      );
    });

    test('falls back to All when the selected project is deleted', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectProject('p1');

      await h.workspace.requestDeleteProject('p1');

      final selection = h.workspace.state.selection;
      expect(selection, isA<SmartViewSelection>());
      expect((selection as SmartViewSelection).view, SmartView.all);
    });

    test('the last remaining project cannot be deleted', () async {
      final h = await loadedHarness(
        tasks: [makeTask(id: 'a')],
        projects: [testProjects.first],
      );

      final result = await h.workspace.requestDeleteProject('p1');

      expect(errValue(result), WorkspaceError.lastProject);
      expect(h.workspace.state.projects.length, 1);
      expect(h.workspace.state.tasks.containsKey('a'), isTrue);
    });

    test('a failed delete changes nothing', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.repository.failNextDelete = true;

      final result = await h.workspace.requestDeleteProject('p1');

      expect(errValue(result), WorkspaceError.deleteFailed);
      expect(h.workspace.state.projects.length, 2);
      expect(h.workspace.state.tasks.length, sampleTasks().length);
    });

    test('a dirty draft of a task in another project blocks it', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      h.workspace.requestSelectTask('c');
      h.workspace.editDraft(title: 'Edited');

      final result = await h.workspace.requestDeleteProject('p1');

      expect(errValue(result), WorkspaceError.unsavedChangesPending);
      expect(h.workspace.state.projects.length, 2);
    });

    test('an unknown project is reported', () async {
      final h = await loadedHarness(tasks: sampleTasks());

      final result = await h.workspace.requestDeleteProject('nope');

      expect(errValue(result), WorkspaceError.unknownProject);
    });
  });

  group('dashboard numbers', () {
    test('progress counts done over all non-archived tasks', () async {
      final h = await loadedHarness(
        tasks: [
          makeTask(id: 'a'),
          makeTask(id: 'b', status: TaskStatus.done),
          makeTask(id: 'c', status: TaskStatus.archived),
        ],
      );

      final progress = h.workspace.state.progress;

      expect(progress.done, 1);
      expect(progress.total, 2);
    });
  });
}
