import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

/// Activating a related subtask reveals the whole path to it, deliberately: it
/// never clears the user's search or filters, and never discards a draft.
Future<(Harness, TasksNotifier)> _deep() async {
  final h = await loadedHarness(
    tasks: [
      makeTask(id: 'a', title: 'A root'),
      makeTask(id: 'b', parentId: 'a', title: 'B child'),
      makeTask(id: 'c', parentId: 'b', title: 'C grandchild'),
      makeTask(id: 'd', parentId: 'c', title: 'D great grandchild'),
      makeTask(id: 'other', projectId: 'p2', title: 'Other project'),
    ],
  );
  return (h, TasksNotifier(h.workspace));
}

List<String> _ids(Harness h) => [
  for (final r in h.workspace.state.visibleRows) r.task.id,
];

void main() {
  test(
    'every collapsed ancestor opens, however deep, and the task is selected',
    () async {
      final (h, n) = await _deep();
      // Collapse the whole chain, as the user may have.
      for (final id in ['a', 'b', 'c']) {
        if (h.workspace.state.expandedTaskIds.contains(id)) {
          n.toggleExpanded(id);
        }
      }
      h.workspace.requestSelectProject('p1');
      expect(_ids(h), ['a']);

      n.revealSubtask('d');

      expect(_ids(h), ['a', 'b', 'c', 'd']);
      expect(n.state.selectedTaskId, 'd');
      expect(n.state.selectedTaskHidden, isFalse);
      expect(n.state.hiddenReasons, isEmpty);
    },
  );

  test(
    'one level works too, and already-open ancestors are left alone',
    () async {
      final (h, n) = await _deep();
      h.workspace.requestSelectProject('p1');
      n.revealSubtask('b');
      expect(n.state.selectedTaskId, 'b');
      expect(n.state.expandedTaskIds, contains('a'));
    },
  );

  test('the search is NOT cleared; a task the search hides says so', () async {
    final (h, n) = await _deep();
    h.workspace.requestSelectProject('p1');
    h.workspace.requestSelectTask('a');
    h.workspace.requestSearch('A root');

    n.revealSubtask('b');

    expect(n.state.searchQuery, 'A root'); // untouched
    expect(n.state.selectedTaskId, 'b');
    expect(n.state.hiddenReasons, {HiddenReason.searchMismatch});
  });

  test('the status filter is NOT cleared; the notice names it', () async {
    final (h, n) = await _deep();
    h.workspace.requestSelectProject('p1');
    h.workspace.requestStatusFilter(TaskStatus.done);
    h.workspace.requestSelectTask('a');

    n.revealSubtask('b');

    expect(n.state.statusFilter, TaskStatus.done);
    expect(n.state.selectedTaskId, 'b');
    expect(n.state.hiddenReasons, contains(HiddenReason.statusFiltered));
  });

  test(
    'a task outside the current view is selected and the view is kept',
    () async {
      final (h, n) = await _deep();
      h.workspace.requestSelectProject('p2');
      n.revealSubtask('b');
      expect(n.state.selectedTaskId, 'b');
      expect(n.state.hiddenReasons, contains(HiddenReason.notInView));
      expect(
        (n.state.selection as dynamic).projectId,
        'p2',
      ); // not switched silently
    },
  );

  test('a collapsed ancestor chosen later is offered as the way out', () async {
    final (h, n) = await _deep();
    h.workspace.requestSelectProject('p1');
    h.workspace.requestSelectTask('d');
    n.toggleExpanded('b'); // the user collapses b afterwards
    expect(n.state.hiddenReasons, {HiddenReason.collapsedAncestor});
    n.expandAncestorsOf('d');
    expect(n.state.hiddenReasons, isEmpty);
  });

  test('each way out changes exactly one thing', () async {
    final (h, n) = await _deep();
    h.workspace.requestSelectProject('p2');
    h.workspace.requestStatusFilter(TaskStatus.done);
    h.workspace.requestSearch('zzz');
    h.workspace.requestSelectTask('other');
    n.revealSubtask('b');
    // all three causes at once
    expect(n.state.hiddenReasons, {
      HiddenReason.notInView,
      HiddenReason.searchMismatch,
      HiddenReason.statusFiltered,
    });
    n.search('');
    expect(n.state.hiddenReasons, {
      HiddenReason.notInView,
      HiddenReason.statusFiltered,
    });
    expect(
      n.state.statusFilter,
      TaskStatus.done,
    ); // untouched by clearing the search
    n.filterStatus(null);
    expect(n.state.hiddenReasons, {HiddenReason.notInView});
    n.selectProject('p1');
    expect(n.state.hiddenReasons, isEmpty);
  });

  test(
    'unsaved edits are protected: the gate opens, the draft stays',
    () async {
      final (h, n) = await _deep();
      h.workspace.requestSelectProject('p1');
      h.workspace.requestSelectTask('a');
      h.workspace.editDraft(title: 'Edited A');
      n.toggleExpanded('a');
      n.toggleExpanded('a'); // collapse and reopen to start from a known state

      n.revealSubtask('c');

      expect(
        n.state.pending,
        isNotNull,
        reason: 'the unsaved-change gate decides',
      );
      expect(n.state.selectedTaskId, 'a');
      expect(n.state.draft!.title, 'Edited A');
      expect(n.state.draft!.isDirty, isTrue);
      // The path is open already, so after Discard the task is simply there.
      await h.workspace.resolvePending(PendingResolution.discard);
      expect(n.state.selectedTaskId, 'c');
      expect(_ids(h), contains('c'));
    },
  );

  test('a task that does not exist is ignored', () async {
    final (h, n) = await _deep();
    n.revealSubtask('nope');
    expect(n.state.selectedTaskId, isNull);
    expect(h, isNotNull);
  });
}
