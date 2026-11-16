import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

/// Search sits on its own row; filters and sort wrap beneath it without
/// overlap at every supported width; combined search, filter and sort behave as
/// before.
Future<TasksNotifier> _pump(WidgetTester tester, double w) async {
  final harness = await loadedHarness(
    tasks: [
      makeTask(id: 'a', title: 'Alpha plan', dueDate: testToday),
      makeTask(
        id: 'b',
        title: 'Alpha report',
        status: TaskStatus.done,
        dueDate: testToday.addDays(2),
      ),
      makeTask(id: 'c', title: 'Beta plan', status: TaskStatus.review),
    ],
  );
  final notifier = TasksNotifier(harness.workspace);
  tester.view.physicalSize = Size(w, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(NexoraApp(notifier: notifier));
  await tester.pumpAndSettle();
  return notifier;
}

Rect _r(WidgetTester tester, Finder f) => tester.getRect(f);

void main() {
  for (final width in [1920.0, 1366.0, 1100.0, 1024.0, 900.0, 700.0]) {
    testWidgets('no overlap and no overflow at ${width.toInt()} px', (
      tester,
    ) async {
      await _pump(tester, width);
      final search = _r(tester, find.byKey(const ValueKey('search-field')));
      final tools = _r(tester, find.byKey(const ValueKey('list-tools')));
      final chips = [
        for (final key in [
          'filter-all',
          'filter-open',
          'filter-inProgress',
          'filter-review',
          'filter-done',
        ])
          _r(tester, find.byKey(ValueKey(key))),
      ];
      final sort = _r(tester, find.byKey(const ValueKey('sort-menu')));

      // Search is its own row, above the tools.
      expect(search.bottom, lessThanOrEqualTo(tools.top));
      // Nothing collides.
      final all = [...chips, sort];
      for (var i = 0; i < all.length; i++) {
        for (var j = i + 1; j < all.length; j++) {
          expect(
            all[i].overlaps(all[j]),
            isFalse,
            reason: 'control $i overlaps $j at $width px',
          );
        }
      }
      // Everything stays inside the list pane's horizontal extent.
      final pane = _r(tester, find.byKey(const ValueKey('task-list-pane')));
      for (final rect in [search, ...all]) {
        expect(rect.left, greaterThanOrEqualTo(pane.left - 0.5));
        expect(rect.right, lessThanOrEqualTo(pane.right + 0.5));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('narrow: the sort control wraps to its own line', (tester) async {
    await _pump(tester, 700);
    final chips = _r(tester, find.byKey(const ValueKey('filter-done')));
    final sort = _r(tester, find.byKey(const ValueKey('sort-menu')));
    expect(sort.top, greaterThanOrEqualTo(chips.bottom));
  });

  testWidgets('wide: filters and sort share one row below the search', (
    tester,
  ) async {
    await _pump(tester, 1920);
    final chips = _r(tester, find.byKey(const ValueKey('filter-all')));
    final sort = _r(tester, find.byKey(const ValueKey('sort-menu')));
    expect((sort.center.dy - chips.center.dy).abs(), lessThan(8));
  });

  testWidgets('search, status filter and sort still combine', (tester) async {
    final notifier = await _pump(tester, 1400);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('search-field')),
        matching: find.byType(EditableText),
      ),
      'alpha',
    );
    await tester.pumpAndSettle();
    expect(notifier.state.visibleRows.map((r) => r.task.id).toSet(), {
      'a',
      'b',
    });

    await tester.tap(find.byKey(const ValueKey('filter-done')));
    await tester.pumpAndSettle();
    expect(notifier.state.visibleRows.map((r) => r.task.id), ['b']);

    await tester.tap(find.byKey(const ValueKey('filter-all')));
    await tester.tap(find.byKey(const ValueKey('sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.sortLabel(TaskSort.title)).last);
    await tester.pumpAndSettle();
    expect(notifier.state.visibleRows.map((r) => r.task.id), ['a', 'b']);
    expect(notifier.state.searchQuery, 'alpha');
  });
}
