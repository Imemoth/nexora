import 'dart:ui' show Size;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/workspace_harness.dart';

Future<void> _pump(WidgetTester tester, Harness harness) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace)),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('accessibility', () {
    testWidgets('every icon-only button has a tooltip', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      await tester.tap(find.byKey(const ValueKey('row-a')));
      await tester.pumpAndSettle();

      final buttons = tester.widgetList<IconButton>(find.byType(IconButton));

      expect(buttons, isNotEmpty);
      for (final button in buttons) {
        expect(button.tooltip, isNotNull, reason: 'IconButton without tooltip');
      }
    });

    testWidgets('the sort menu has a tooltip and is labelled', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);

      final menu = tester.widget<PopupMenuButton<Object>>(
        find.byKey(const ValueKey('sort-menu')),
      );

      expect(menu.tooltip, AppStrings.sortTooltip);
    });

    testWidgets('row chevrons are at least 40 by 40 logical pixels', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);

      final size = tester.getSize(find.byKey(const ValueKey('chevron-parent')));

      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));
    });

    testWidgets('task rows are at least 40 logical pixels tall', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);

      final size = tester.getSize(find.byKey(const ValueKey('row-a')));

      expect(size.height, greaterThanOrEqualTo(40));
    });

    testWidgets('the close button of the details overlay is labelled', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        NexoraApp(notifier: TasksNotifier(harness.workspace)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('row-a')));
      await tester.pumpAndSettle();

      expect(find.byTooltip(AppStrings.closeDetails), findsOneWidget);
    });
  });
}
