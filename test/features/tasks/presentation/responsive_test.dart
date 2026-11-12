import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/unsaved_changes_host.dart';

import '../../../support/workspace_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  Harness harness, {
  double width = 1280,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(
      notifier: TasksNotifier(harness.workspace),
      textScaler: TextScaler.linear(textScale),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectRow(WidgetTester tester, String taskId) async {
  await tester.tap(find.byKey(ValueKey('row-$taskId')));
  await tester.pumpAndSettle();
}

void main() {
  group('responsive breakpoints', () {
    testWidgets('at 1000 px a selected task opens the details overlay', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness, width: 1000);

      await _selectRow(tester, 'a');

      expect(find.byKey(const ValueKey('details-overlay')), findsOneWidget);
      expect(find.byKey(const ValueKey('details-pane')), findsNothing);
      expect(find.byKey(const ValueKey('task-list-pane')), findsOneWidget);
    });

    testWidgets('closing the overlay clears the selection', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness, width: 1000);
      await _selectRow(tester, 'a');

      await tester.tap(find.byTooltip(AppStrings.closeDetails));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('details-overlay')), findsNothing);
      expect(harness.workspace.state.selectedTaskId, isNull);
    });

    testWidgets('closing a dirty overlay opens the unsaved-change dialog', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness, width: 1000);
      await _selectRow(tester, 'a');
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('title-a')),
          matching: find.byType(TextField),
        ),
        'Alpha 2',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip(AppStrings.closeDetails));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets('focus returns to the task list after the overlay closes', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness, width: 1000);
      await _selectRow(tester, 'a');

      await tester.tap(find.byTooltip(AppStrings.closeDetails));
      await tester.pumpAndSettle();

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'task-list',
      );
    });

    testWidgets('below 900 px a desktop-only notice shows and no overlay opens', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness, width: 800);

      expect(find.text(AppStrings.desktopOnlyNotice), findsOneWidget);
      await _selectRow(tester, 'a');

      expect(find.byKey(const ValueKey('details-overlay')), findsNothing);
      expect(find.byKey(const ValueKey('task-list-pane')), findsOneWidget);
    });

    testWidgets('at 1280 px there is no desktop-only notice', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);

      expect(find.text(AppStrings.desktopOnlyNotice), findsNothing);
    });
  });

  group('text scaling', () {
    for (final width in [1280.0, 1000.0]) {
      testWidgets('text scale 1.3 at $width px does not overflow', (
        tester,
      ) async {
        final harness = await loadedHarness(tasks: sampleTasks());
        await _pump(tester, harness, width: width, textScale: 1.3);
        await _selectRow(tester, 'a');

        expect(tester.takeException(), isNull);
      });
    }
  });
}
