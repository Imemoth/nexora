import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

/// Activating a related subtask in the details panel: the path opens in the tree,
/// the task is selected and in view, the keyboard follows, nothing the user chose
/// (search, filters, view, unsaved edits) is silently undone.
Future<(Harness, TasksNotifier)> _pump(
  WidgetTester tester, {
  ThemePreference theme = ThemePreference.dark,
  double w = 1400,
  double h = 900,
  int filler = 0,
}) async {
  final harness = await loadedHarness(
    tasks: [
      for (var i = 0; i < filler; i++)
        makeTask(id: 'f$i', title: 'Filler $i', position: i),
      makeTask(id: 'a', title: 'Top task', position: filler),
      makeTask(id: 'b', parentId: 'a', title: 'Middle task'),
      makeTask(id: 'c', parentId: 'b', title: 'Inner task'),
      makeTask(id: 'd', parentId: 'c', title: 'Deepest task'),
      makeTask(id: 'other', projectId: 'p2', title: 'Elsewhere'),
    ],
  );
  final notifier = TasksNotifier(harness.workspace);
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: notifier,
      themeController: ThemeController(InMemorySettingsStore(), initial: theme),
    ),
  );
  await tester.pumpAndSettle();
  return (harness, notifier);
}

Future<void> _collapse(
  WidgetTester tester,
  TasksNotifier n,
  List<String> ids,
) async {
  for (final id in ids) {
    if (n.state.expandedTaskIds.contains(id)) {
      n.toggleExpanded(id);
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in [ThemePreference.dark, ThemePreference.light]) {
    testWidgets(
      'clicking a nested related subtask opens the whole path (${theme.name})',
      (tester) async {
        final (_, n) = await _pump(tester, theme: theme);
        n.selectProject('p1');
        n.selectTask('a');
        await tester.pumpAndSettle();
        await _collapse(tester, n, ['a', 'b', 'c']);
        expect(find.byKey(const ValueKey('row-b')), findsNothing);

        // the details of A list B as a related subtask
        await tester.tap(find.byKey(const ValueKey('subtask-b')));
        await tester.pumpAndSettle();
        expect(n.state.selectedTaskId, 'b');
        expect(find.byKey(const ValueKey('row-b')), findsOneWidget); // A opened

        // B's details list C; go two levels in
        await tester.tap(find.byKey(const ValueKey('subtask-c')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtask-d')));
        await tester.pumpAndSettle();
        expect(n.state.selectedTaskId, 'd');
        for (final id in ['a', 'b', 'c', 'd']) {
          expect(find.byKey(ValueKey('row-$id')), findsOneWidget, reason: id);
        }
        expect(find.byKey(const ValueKey('hidden-notice')), findsNothing);
      },
    );
  }

  testWidgets(
    'the keyboard follows: the list owns focus and the selected row shows its ring',
    (tester) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      final (_, n) = await _pump(tester);
      n.selectProject('p1');
      n.selectTask('a');
      await tester.pumpAndSettle();
      await _collapse(tester, n, ['a']);
      await tester.tap(find.byKey(const ValueKey('subtask-b')));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'task-list');
      // the arrow keys continue from the revealed task: Right opens B, Right
      // again moves to its first child
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(n.state.selectedTaskId, 'c');
    },
  );

  testWidgets('keyboard activation of the related subtask row works (Enter)', (
    tester,
  ) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final (_, n) = await _pump(tester);
    n.selectProject('p1');
    n.selectTask('a');
    await tester.pumpAndSettle();
    await _collapse(tester, n, ['a']);
    final inner = find.descendant(
      of: find.byKey(const ValueKey('subtask-b')),
      matching: find.byType(Text),
    );
    Focus.of(tester.element(inner.first)).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(n.state.selectedTaskId, 'b');
    expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
  });

  testWidgets('the revealed row is scrolled into view in a long list', (
    tester,
  ) async {
    final (_, n) = await _pump(tester, filler: 60, h: 700);
    n.selectProject('p1');
    n.selectTask('a');
    await tester.pumpAndSettle();
    await _collapse(tester, n, ['a']);
    // "Top task" is far down the list; its related subtask is revealed
    await tester.ensureVisible(find.byKey(const ValueKey('subtask-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subtask-b')));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('row-b'));
    expect(row, findsOneWidget);
    final list = tester.getRect(find.byKey(const ValueKey('task-list-pane')));
    final rect = tester.getRect(row);
    expect(rect.top, greaterThanOrEqualTo(list.top));
    expect(rect.bottom, lessThanOrEqualTo(list.bottom));
  });

  group('a task the current search, filter or view cannot show', () {
    testWidgets(
      'the search stays; the notice offers to clear it, and clearing keeps the selection',
      (tester) async {
        final (_, n) = await _pump(tester);
        n.selectProject('p1');
        n.selectTask('a');
        n.search('Top');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtask-b')));
        await tester.pumpAndSettle();

        expect(n.state.searchQuery, 'Top'); // untouched
        expect(find.byKey(const ValueKey('hidden-notice')), findsOneWidget);
        expect(find.text(AppStrings.selectedTaskHidden), findsOneWidget);
        expect(
          find.byKey(const ValueKey('reveal-clear-search')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('reveal-clear-filter')), findsNothing);

        await tester.tap(find.byKey(const ValueKey('reveal-clear-search')));
        await tester.pumpAndSettle();
        expect(n.state.searchQuery, '');
        expect(n.state.selectedTaskId, 'b');
        expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
        expect(find.byKey(const ValueKey('hidden-notice')), findsNothing);
      },
    );

    testWidgets('the status filter stays; one action shows all statuses', (
      tester,
    ) async {
      final (_, n) = await _pump(tester);
      n.selectProject('p1');
      n.filterStatus(TaskStatus.done);
      n.selectTask('a');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('subtask-b')));
      await tester.pumpAndSettle();
      expect(n.state.statusFilter, TaskStatus.done);
      expect(find.byKey(const ValueKey('reveal-clear-filter')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reveal-clear-filter')));
      await tester.pumpAndSettle();
      expect(n.state.statusFilter, isNull);
      expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
    });

    testWidgets(
      'another project: the view stays, "Show in <project>" opens it',
      (tester) async {
        final (_, n) = await _pump(tester);
        n.selectProject('p1');
        n.selectTask('a');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('nav-project-p2')));
        await tester.pumpAndSettle();
        // selecting a task of p1 again from the details is not possible once it is
        // hidden by the view; reveal it directly (a notification would do the same)
        n.revealSubtask('b');
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('reveal-project')), findsOneWidget);
        expect(
          find.text(AppStrings.revealShowInProject('Home')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('reveal-project')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
        expect(n.state.selectedTaskId, 'b');
      },
    );

    testWidgets(
      'a parent collapsed afterwards: "Expand parents" reopens the path',
      (tester) async {
        final (_, n) = await _pump(tester);
        n.selectProject('p1');
        n.selectTask('a');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('subtask-b')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chevron-a')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('reveal-expand')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('reveal-expand')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('row-b')), findsOneWidget);
      },
    );
  });

  testWidgets(
    'unsaved edits are protected: the gate opens and the draft survives',
    (tester) async {
      final (h, n) = await _pump(tester);
      n.selectProject('p1');
      n.selectTask('a');
      n.editDraft(title: 'Edited top');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('subtask-b')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(n.state.selectedTaskId, 'a');
      expect(n.state.draft!.title, 'Edited top');
      // Cancel keeps editing; nothing was lost
      await tester.tap(find.text(AppStrings.cancelAction));
      await tester.pumpAndSettle();
      expect(n.state.draft!.title, 'Edited top');
      expect(h.repository.savedTasks, isEmpty);
    },
  );

  testWidgets('works in the overlay layout (1024 px) too', (tester) async {
    final (_, n) = await _pump(tester, w: 1024, h: 768);
    n.selectProject('p1');
    n.selectTask('a');
    await tester.pumpAndSettle();
    await _collapse(tester, n, ['a', 'b']);
    await tester.tap(find.byKey(const ValueKey('subtask-b')));
    await tester.pumpAndSettle();
    expect(n.state.selectedTaskId, 'b');
    expect(find.byKey(const ValueKey('details-overlay')), findsOneWidget);
    expect(n.state.expandedTaskIds, contains('a'));
  });
}
