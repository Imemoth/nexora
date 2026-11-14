import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

Future<void> _pump(WidgetTester tester, Harness harness) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('status filter chips', () {
    testWidgets('a chip filters the list and All restores it', (tester) async {
      final harness = await loadedHarness(
        tasks: [
          makeTask(id: 'o', title: 'Open one'),
          makeTask(id: 'd', title: 'Done one', status: TaskStatus.done),
        ],
      );
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('filter-done')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('row-d')), findsOneWidget);
      expect(find.byKey(const ValueKey('row-o')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('row-o')), findsOneWidget);
    });

    testWidgets('each chip shows its count', (tester) async {
      final harness = await loadedHarness(
        tasks: [
          makeTask(id: 'a'),
          makeTask(id: 'b'),
          makeTask(id: 'c', status: TaskStatus.done),
        ],
      );
      await _pump(tester, harness);

      expect(
        find.text(AppStrings.filterChipLabel(AppStrings.filterAll, 3)),
        findsOneWidget,
      );
      expect(
        find.text(
          AppStrings.filterChipLabel(
            AppStrings.statusLabel(TaskStatus.open),
            2,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('quick add', () {
    testWidgets('Enter creates a task and clears the field', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      final before = harness.workspace.state.tasks.length;

      await tester.enterText(
        find.byKey(const ValueKey('quick-add')),
        'Water the plants',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      final tasks = harness.workspace.state.tasks.values;
      expect(tasks.length, before + 1);
      expect(tasks.any((t) => t.title == 'Water the plants'), isTrue);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('quick-add')),
      );
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('an empty title shows the error and creates nothing', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      final before = harness.workspace.state.tasks.length;

      await tester.tap(find.byKey(const ValueKey('quick-add')));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.titleRequired), findsOneWidget);
      expect(harness.workspace.state.tasks.length, before);
    });
  });
}
