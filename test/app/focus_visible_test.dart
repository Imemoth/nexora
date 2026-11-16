import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/palette.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/workspace_harness.dart';

/// Keyboard focus must be visible on the controls of the workspace in both
/// themes. Measured on rendered pixels: focusing a control must add pixels of
/// the focus-ring colour (accent cyan) around it.
Future<(TasksNotifier, ThemePreference)> _pump(
  WidgetTester tester,
  ThemePreference theme,
) async {
  final harness = await loadedHarness(tasks: sampleTasks());
  final notifier = TasksNotifier(harness.workspace);
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: notifier,
      themeController: ThemeController(InMemorySettingsStore(), initial: theme),
    ),
  );
  await tester.pumpAndSettle();
  notifier.selectTask('a'); // dated
  notifier.editDraft(notes: 'edited'); // Save and Revert enabled
  await tester.pumpAndSettle();
  return (notifier, theme);
}

Future<int> _ringPixels(WidgetTester tester, Rect area, int ringArgb) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = (await tester.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  final rr = (ringArgb >> 16) & 0xFF;
  final rg = (ringArgb >> 8) & 0xFF;
  final rb = ringArgb & 0xFF;
  var count = 0;
  final box = area.inflate(5);
  for (var y = box.top.floor(); y < box.bottom.ceil(); y++) {
    for (var x = box.left.floor(); x < box.right.ceil(); x++) {
      if (x < 0 || y < 0 || x >= image!.width || y >= image.height) {
        continue;
      }
      final i = (y * image.width + x) * 4;
      if ((bytes.getUint8(i) - rr).abs() <= 32 &&
          (bytes.getUint8(i + 1) - rg).abs() <= 32 &&
          (bytes.getUint8(i + 2) - rb).abs() <= 32) {
        count++;
      }
    }
  }
  return count;
}

/// Focuses the control whose widget has [key], through a widget inside it.
Future<void> _focus(WidgetTester tester, Finder control) async {
  final inner = find.descendant(of: control, matching: find.byType(Text)).first;
  Focus.of(tester.element(inner)).requestFocus();
  await tester.pumpAndSettle();
}

void main() {
  // Windows users navigate by keyboard: the traditional highlight mode. The
  // test platform defaults to touch, which hides focus highlights.
  setUp(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional,
  );
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  const controls = <String, ValueKey<String>>{
    'status filter chip': ValueKey('filter-open'),
    'status filter "All" chip': ValueKey('filter-all'),
    'sort button': ValueKey('sort-menu'),
    'sidebar view': ValueKey('nav-today'),
    'sidebar project': ValueKey('nav-project-p1'),
    'sidebar dashboard': ValueKey('nav-dashboard'),
    'add subtask': ValueKey('add-subtask'),
    'due date button': ValueKey('due-date-button'),
    'due time button': ValueKey('due-time-button'),
    'save': ValueKey('save'),
  };

  for (final theme in [ThemePreference.dark, ThemePreference.light]) {
    final palette = theme == ThemePreference.dark
        ? NexoraPalette.dark
        : NexoraPalette.light;
    for (final entry in controls.entries) {
      testWidgets('${entry.key} shows a focus ring (${theme.name})', (
        tester,
      ) async {
        await _pump(tester, theme);
        final control = find.byKey(entry.value);
        expect(control, findsOneWidget);
        final rect = tester.getRect(control);
        final before = await _ringPixels(tester, rect, palette.accentCyan);
        await _focus(tester, control);
        final after = await _ringPixels(tester, rect, palette.accentCyan);
        expect(
          after - before,
          greaterThanOrEqualTo(30),
          reason: '${entry.key}: before $before, after $after ring pixels',
        );
      });
    }
  }
}
