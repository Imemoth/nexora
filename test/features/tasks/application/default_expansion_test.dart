import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

/// The default expansion: a parent at the top of the list shows its direct
/// children, once. It never cascades and never undoes a collapse the user chose.
List<String> _ids(Harness h) => [
  for (final r in h.workspace.state.visibleRows) r.task.id,
];

void main() {
  // root -> mid -> leaf, plus a second root with one child, plus a loner.
  List tree() => [
    makeTask(id: 'root', title: 'Root', position: 0),
    makeTask(id: 'mid', parentId: 'root', title: 'Mid'),
    makeTask(id: 'leaf', parentId: 'mid', title: 'Leaf'),
    makeTask(id: 'r2', title: 'Second', position: 1),
    makeTask(id: 'r2c', parentId: 'r2', title: 'Second child'),
    makeTask(id: 'solo', title: 'Solo', position: 2),
  ];

  test('direct children of a top-level parent are visible at once', () async {
    final h = await loadedHarness(tasks: [...tree()].cast());
    expect(_ids(h), containsAll(['root', 'mid', 'r2', 'r2c', 'solo']));
  });

  test('deeper levels are NOT opened: a child that is itself a parent stays collapsed', () async {
    final h = await loadedHarness(tasks: [...tree()].cast());
    final ids = _ids(h);
    expect(ids, isNot(contains('leaf')));
    final mid = h.workspace.state.visibleRows.firstWhere(
      (r) => r.task.id == 'mid',
    );
    expect(mid.hasChildren, isTrue);
    expect(mid.expanded, isFalse);
    expect(mid.depth, 1);
  });

  test('a leaf and a task without children are not marked expanded', () async {
    final h = await loadedHarness(tasks: [...tree()].cast());
    expect(h.workspace.state.expandedTaskIds, {'root', 'r2'});
  });

  test('deeper levels open on request and stay open', () async {
    final h = await loadedHarness(tasks: [...tree()].cast());
    h.workspace.toggleExpanded('mid');
    expect(_ids(h), contains('leaf'));
    h.workspace.requestSort(TaskSort.title);
    expect(_ids(h), contains('leaf'));
  });

  group('an explicit collapse is not undone', () {
    test('by a refresh with incoming data', () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      h.workspace.toggleExpanded('root'); // the user collapses it
      await h.repository.saveTask(
        makeTask(id: 'new', title: 'Incoming', position: 5),
      );
      await h.workspace.refresh();
      expect(_ids(h), isNot(contains('mid')));
      expect(_ids(h), contains('new'));
    });

    test('by sorting, searching, filtering and changing the view', () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      final ws = h.workspace;
      ws.toggleExpanded('root');
      ws.requestSort(TaskSort.title);
      ws.requestSort(TaskSort.position);
      ws.requestSearch('Root');
      ws.requestSearch('');
      ws.requestStatusFilter(TaskStatus.open);
      ws.requestStatusFilter(null);
      ws.requestSelectProject('p2');
      ws.requestSelectProject('p1');
      expect(_ids(h), isNot(contains('mid')));
      expect(ws.state.expandedTaskIds, isNot(contains('root')));
    });

    test('and a collapsed parent can be opened again by the user', () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      h.workspace.toggleExpanded('root');
      h.workspace.toggleExpanded('root');
      expect(_ids(h), contains('mid'));
    });
  });

  group('when the default applies', () {
    test('a parent that gains its first child opens to show it', () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      expect(h.workspace.state.expandedTaskIds, isNot(contains('solo')));
      await h.repository.saveTask(
        makeTask(id: 'solo-child', parentId: 'solo', title: 'New child'),
      );
      await h.workspace.refresh();
      expect(_ids(h), contains('solo-child'));
    });

    test(
      'a parent whose children are filtered out opens the first time they show',
      () async {
        final h = await loadedHarness(
          tasks: [
            makeTask(id: 'p', title: 'P'),
            makeTask(
              id: 'c',
              parentId: 'p',
              title: 'C',
              status: TaskStatus.done,
            ),
          ],
        );
        h.workspace.requestStatusFilter(TaskStatus.open);
        expect(_ids(h), [
          'p',
        ]); // the filter hides the child; nothing to expand yet
        h.workspace.requestStatusFilter(null);
        expect(_ids(h), ['p', 'c']);
      },
    );

    test(
      'a child shown at the top because its parent is filtered out opens once',
      () async {
        final h = await loadedHarness(
          tasks: [
            makeTask(id: 'root', title: 'Root'),
            makeTask(id: 'mid', parentId: 'root', title: 'Mid'),
            makeTask(id: 'leaf', parentId: 'mid', title: 'Mid leaf'),
          ],
        );
        // Searching "Mid" hides Root, so Mid stands at the top, with its child.
        h.workspace.requestSearch('Mid');
        expect(_ids(h), ['mid', 'leaf']);
        h.workspace.toggleExpanded('mid'); // the user collapses it there
        h.workspace.requestSearch('');
        expect(_ids(h), isNot(contains('leaf'))); // not undone
      },
    );

    test('a fresh load presents the tree anew', () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      h.workspace.toggleExpanded('root');
      await h.workspace.load();
      expect(_ids(h), contains('mid'));
    });

    test('the Dashboard has no list and expands nothing', () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      h.workspace.requestSelectDashboard();
      expect(h.workspace.state.visibleRows, isEmpty);
    });
  });

  test(
    'selection and the draft are untouched by the default expansion',
    () async {
      final h = await loadedHarness(tasks: [...tree()].cast());
      h.workspace.requestSelectTask('solo');
      h.workspace.editDraft(title: 'Edited');
      await h.repository.saveTask(
        makeTask(id: 'solo-child', parentId: 'solo', title: 'x'),
      );
      await h.workspace.refresh();
      expect(h.workspace.state.selectedTaskId, 'solo');
      expect(h.workspace.state.draft!.title, 'Edited');
      expect(_ids(h), contains('solo-child')); // the parent opened
    },
  );

  test(
    'ordering stays deterministic: children follow their parent by position',
    () async {
      final h = await loadedHarness(
        tasks: [
          makeTask(id: 'p', title: 'P'),
          makeTask(id: 'c2', parentId: 'p', title: 'B', position: 1),
          makeTask(id: 'c1', parentId: 'p', title: 'A', position: 0),
        ],
      );
      expect(_ids(h), ['p', 'c1', 'c2']);
    },
  );
}
