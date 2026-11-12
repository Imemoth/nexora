import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/workspace_harness.dart';

/// Demo data for [testToday]: 12 tasks, 1 due today, 2 overdue, 2 due in the
/// next seven days, Home has 7 tasks and Work has 5.
Future<TaskWorkspace> _pumpApp(
  WidgetTester tester, {
  double width = 1280,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final demo = buildDemoData(testToday);
  final harness = await loadedHarness(
    tasks: demo.tasks,
    projects: demo.projects,
  );
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace)),
  );
  await tester.pumpAndSettle();
  return harness.workspace;
}

Finder _text(String text) => find.text(text);

void main() {
  testWidgets('shows sidebar, task list and details panes at 1280 px', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-list-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('details-pane')), findsOneWidget);
  });

  testWidgets('opens on All with the full task count', (tester) async {
    await _pumpApp(tester);

    expect(
      _textOf(tester, 'list-title'),
      AppStrings.smartViewLabel(SmartView.all),
    );
    expect(_textOf(tester, 'list-count'), AppStrings.taskCount(12));
  });

  testWidgets('tapping Today updates the header, the count and the selection', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('nav-today')));
    await tester.pumpAndSettle();

    expect(
      (workspace.state.selection as SmartViewSelection).view,
      SmartView.today,
    );
    expect(
      _textOf(tester, 'list-title'),
      AppStrings.smartViewLabel(SmartView.today),
    );
    expect(_textOf(tester, 'list-count'), AppStrings.taskCount(1));
  });

  testWidgets('sidebar counts equal the workspace counts', (tester) async {
    final workspace = await _pumpApp(tester);

    for (final view in SmartView.values) {
      final tile = find.byKey(ValueKey('nav-${view.name}'));
      final expected = workspace.state.countFor(SmartViewSelection(view));
      expect(
        find.descendant(of: tile, matching: _text('$expected')),
        findsOneWidget,
        reason: view.name,
      );
    }
    final work = find.byKey(const ValueKey('nav-project-project-work'));
    expect(find.descendant(of: work, matching: _text('5')), findsOneWidget);
  });

  testWidgets('tapping a project shows its tasks', (tester) async {
    final workspace = await _pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('nav-project-project-work')));
    await tester.pumpAndSettle();

    expect(
      (workspace.state.selection as ProjectSelection).projectId,
      'project-work',
    );
    expect(_textOf(tester, 'list-title'), 'Work');
    expect(_textOf(tester, 'list-count'), AppStrings.taskCount(5));
  });

  testWidgets('tapping a row selects it and fills the details pane', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('row-home-groceries')));
    await tester.pumpAndSettle();

    // The details pane is an editor (Task 5), so the title is an editable
    // field keyed by task id, not a read-only Text.
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('title-home-groceries')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, 'Plan weekend groceries');
  });

  testWidgets('details pane shows a prompt when nothing is selected', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(_text(AppStrings.selectTaskPrompt), findsOneWidget);
  });

  testWidgets('below 1100 px the details pane is not shown', (tester) async {
    await _pumpApp(tester, width: 800);

    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-list-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('details-pane')), findsNothing);
  });
}

String _textOf(WidgetTester tester, String key) {
  final widget = tester.widget<Text>(find.byKey(ValueKey(key)));
  return widget.data ?? '';
}
