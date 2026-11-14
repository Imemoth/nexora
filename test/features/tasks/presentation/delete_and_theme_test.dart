import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../../../support/workspace_harness.dart';

Future<void> _pump(
  WidgetTester tester,
  Harness harness, {
  ThemeController? themeController,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(
      notifier: TasksNotifier(harness.workspace),
      themeController: themeController,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectRow(WidgetTester tester, String taskId) async {
  await tester.tap(find.byKey(ValueKey('row-$taskId')));
  await tester.pumpAndSettle();
}

void main() {
  group('delete task', () {
    testWidgets('asks first, then removes the task', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      await _selectRow(tester, 'a');

      await tester.tap(find.byKey(const ValueKey('delete-task')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.deleteTaskTitle), findsOneWidget);
      expect(harness.workspace.state.tasks.containsKey('a'), isTrue);

      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.tasks.containsKey('a'), isFalse);
      expect(find.byKey(const ValueKey('row-a')), findsNothing);
      expect(find.text(AppStrings.taskDeleted), findsOneWidget);
    });

    testWidgets('Cancel keeps the task', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      await _selectRow(tester, 'a');

      await tester.tap(find.byKey(const ValueKey('delete-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-cancel')));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.tasks.containsKey('a'), isTrue);
      expect(harness.repository.deletedIds, isEmpty);
    });

    testWidgets('the dialog says how many subtasks go too', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      await _selectRow(tester, 'parent');

      await tester.tap(find.byKey(const ValueKey('delete-task')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.deleteTaskBody(1)), findsOneWidget);
    });
  });

  group('delete project', () {
    testWidgets('asks first, then removes the project and its tasks', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('project-menu-p2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('project-delete-p2')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.deleteProjectTitle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('delete-confirm')));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.projects.map((p) => p.id), ['p1']);
      expect(harness.workspace.state.tasks.containsKey('c'), isFalse);
      expect(find.text(AppStrings.projectDeleted), findsOneWidget);
    });

    testWidgets('the last project cannot be deleted from the menu', (
      tester,
    ) async {
      final harness = await loadedHarness(
        tasks: sampleTasks().where((t) => t.projectId == 'p1').toList(),
        projects: [testProjects.first],
      );
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('project-menu-p1')));
      await tester.pumpAndSettle();

      final item = tester.widget<PopupMenuItem<void>>(
        find.byKey(const ValueKey('project-delete-p1')),
      );
      expect(item.enabled, isFalse);
    });
  });

  group('theme', () {
    testWidgets('the selector shows Light, Dark and System', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);

      expect(find.text(AppStrings.themeLight), findsOneWidget);
      expect(find.text(AppStrings.themeDark), findsOneWidget);
      expect(find.text(AppStrings.themeSystem), findsOneWidget);
    });

    testWidgets('choosing Light restyles the app and saves the choice', (
      tester,
    ) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      final store = InMemorySettingsStore(ThemePreference.dark);
      final controller = ThemeController(store, initial: ThemePreference.dark);
      await _pump(tester, harness, themeController: controller);
      expect(
        NexoraColors.of(tester.element(find.byKey(const ValueKey('sidebar'))))
            .isDark,
        isTrue,
      );

      await tester.tap(find.text(AppStrings.themeLight));
      await tester.pumpAndSettle();

      expect(
        NexoraColors.of(tester.element(find.byKey(const ValueKey('sidebar'))))
            .isDark,
        isFalse,
      );
      expect(await store.loadThemePreference(), ThemePreference.light);
    });

    testWidgets('switching the theme keeps an unsaved draft', (tester) async {
      final harness = await loadedHarness(tasks: sampleTasks());
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      harness.workspace.editDraft(title: 'Edited title');
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.themeLight));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.draft?.title, 'Edited title');
      expect(harness.workspace.state.draft?.isDirty, isTrue);
      expect(harness.workspace.state.pending, isNull);
      expect(find.text(AppStrings.unsavedChangesTitle), findsNothing);
    });
  });

  group('theme controller', () {
    test('System maps to ThemeMode.system', () {
      final controller = ThemeController(InMemorySettingsStore());

      expect(controller.mode, ThemeMode.system);
    });

    test('load restores the saved preference', () async {
      final controller = ThemeController(
        InMemorySettingsStore(ThemePreference.light),
      );

      await controller.load();

      expect(controller.preference, ThemePreference.light);
      expect(controller.mode, ThemeMode.light);
    });
  });
}
