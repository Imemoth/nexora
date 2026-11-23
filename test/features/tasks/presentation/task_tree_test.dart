import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

Future<Harness> _demo() async {
  final demo = buildDemoData(testToday);
  return loadedHarness(tasks: demo.tasks, projects: demo.projects);
}

Future<void> _pump(WidgetTester tester, Harness harness) async {
  // Was 1280x800. Search has its own row, and parents now show their children,
  // so the demo list is longer than the viewport plus the list's cache extent.
  tester.view.physicalSize = const Size(1280, 1300);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace)),
  );
  await tester.pumpAndSettle();
}

Finder _inRow(String taskId, Finder matching) {
  return find.descendant(
    of: find.byKey(ValueKey('row-$taskId')),
    matching: matching,
  );
}

/// Row keys in the order they appear on screen.
List<String> _rowIds(WidgetTester tester) {
  final keys = tester
      .widgetList<Widget>(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('row-'),
        ),
      )
      .map((widget) => (widget.key! as ValueKey<String>).value);
  return [for (final key in keys) key.substring('row-'.length)];
}

void main() {
  group('task tree', () {
    testWidgets('parents show done/total and a chevron, leaves show neither', (
      tester,
    ) async {
      final harness = await _demo();
      await _pump(tester, harness);

      expect(
        _inRow('home-trip', find.text(AppStrings.progress(1, 2))),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('chevron-home-trip')), findsOneWidget);
      expect(find.byKey(const ValueKey('chevron-home-bike')), findsNothing);
    });

    testWidgets('collapsed children are not built', (tester) async {
      final harness = await _demo();
      await _pump(tester, harness);
      await tester.tap(find.byKey(const ValueKey('chevron-home-trip')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('row-home-trip-train')), findsNothing);
      expect(find.byKey(const ValueKey('row-home-trip-bags')), findsNothing);
    });

    testWidgets(
      'the chevron expands and collapses children without selecting',
      (tester) async {
        final harness = await _demo();
        await _pump(tester, harness);

        // Expanded by default: the children are already there.
        expect(
          find.byKey(const ValueKey('row-home-trip-bags')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('chevron-home-trip')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('row-home-trip-bags')), findsNothing);
        expect(harness.workspace.state.selectedTaskId, isNull);

        await tester.tap(find.byKey(const ValueKey('chevron-home-trip')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('row-home-trip-bags')),
          findsOneWidget,
        );
      },
    );

    testWidgets('a row shows status, due date and priority as text', (
      tester,
    ) async {
      final harness = await _demo();
      await _pump(tester, harness);

      expect(
        _inRow(
          'home-utility',
          find.text(AppStrings.statusLabel(TaskStatus.open)),
        ),
        findsOneWidget,
      );
      expect(
        _inRow(
          'home-utility',
          find.text(
            AppStrings.friendlyDue(
              const CalendarDate(2026, 11, 10),
              testToday,
              closed: false,
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(
        _inRow(
          'home-utility',
          find.text(AppStrings.priorityLabel(TaskPriority.high)),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a parent whose children are all done shows the hint and keeps its status',
      (tester) async {
        final harness = await loadedHarness(
          tasks: [
            makeTask(id: 'p', title: 'Parent'),
            makeTask(id: 'c1', parentId: 'p', status: TaskStatus.done),
            makeTask(id: 'c2', parentId: 'p', status: TaskStatus.done),
          ],
          projects: testProjects,
        );
        await _pump(tester, harness);

        expect(
          _inRow('p', find.text(AppStrings.readyForReview)),
          findsOneWidget,
        );
        expect(harness.workspace.state.tasks['p']?.status, TaskStatus.open);
      },
    );

    testWidgets('a collapsed selected task shows the hidden notice', (
      tester,
    ) async {
      final harness = await _demo();
      await _pump(tester, harness);
      // Expanded by default: select the child directly.
      await tester.tap(find.byKey(const ValueKey('row-home-trip-bags')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('chevron-home-trip')));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.selectedTaskId, 'home-trip-bags');
      expect(find.text(AppStrings.selectedTaskHidden), findsOneWidget);
    });
  });

  group('search', () {
    testWidgets('typing narrows the rows and the result count', (tester) async {
      final harness = await _demo();
      await _pump(tester, harness);

      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'bike',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('row-home-bike')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-home-utility')), findsNothing);
      expect(find.text(AppStrings.taskCount(1)), findsOneWidget);
    });

    testWidgets('no matches shows a message and Clear restores the rows', (
      tester,
    ) async {
      final harness = await _demo();
      await _pump(tester, harness);

      await tester.enterText(
        find.byKey(const ValueKey('search-field')),
        'zzzz',
      );
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.noSearchMatches), findsOneWidget);

      await tester.tap(find.text(AppStrings.clearSearch));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.noSearchMatches), findsNothing);
      expect(find.byKey(const ValueKey('row-home-utility')), findsOneWidget);
      expect(harness.workspace.state.searchQuery, '');
    });
  });

  group('sort', () {
    testWidgets('choosing due date reorders the rows', (tester) async {
      final harness = await _demo();
      await _pump(tester, harness);
      expect(_rowIds(tester).first, 'home-groceries');

      await tester.tap(find.byKey(const ValueKey('sort-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.sortLabel(TaskSort.dueDate)));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.sort, TaskSort.dueDate);
      expect(_rowIds(tester).first, 'home-utility');
    });
  });

  group('empty states', () {
    testWidgets('an empty project shows its message', (tester) async {
      final harness = await loadedHarness(
        tasks: const [],
        projects: testProjects,
      );
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('nav-project-p1')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.emptyProject), findsOneWidget);
    });
  });
}
