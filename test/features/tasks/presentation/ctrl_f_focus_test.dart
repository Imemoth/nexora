import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/workspace_harness.dart';

/// Ctrl+F must put visible focus in the search field and let the user type,
/// wherever the keyboard focus was before. (Investigation of an unconfirmed
/// report: the app only binds the key inside the list and details panes.)
Future<TasksNotifier> _pump(WidgetTester tester, {double w = 1400}) async {
  final harness = await loadedHarness(tasks: sampleTasks());
  final notifier = TasksNotifier(harness.workspace);
  tester.view.physicalSize = Size(w, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(NexoraApp(notifier: notifier));
  await tester.pumpAndSettle();
  return notifier;
}

Future<void> _ctrlF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

final _search = find.descendant(
  of: find.byKey(const ValueKey('search-field')),
  matching: find.byType(EditableText),
);

bool _searchFocused(WidgetTester tester) =>
    tester.widget<EditableText>(_search).focusNode.hasPrimaryFocus;

Future<void> _expectTypingWorks(WidgetTester tester) async {
  expect(_searchFocused(tester), isTrue, reason: 'search has focus');
  await tester.enterText(_search, 'alp');
  await tester.pumpAndSettle();
  expect(
    tester.widget<EditableText>(_search).controller.text,
    'alp',
    reason: 'search accepts input',
  );
}

void main() {
  testWidgets('from the initial state', (tester) async {
    await _pump(tester);
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });

  testWidgets('after clicking a project in the sidebar', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-project-p1')));
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });

  testWidgets('after clicking a smart view in the sidebar', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('nav-today')));
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });

  testWidgets('after clicking a status filter chip', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('filter-open')));
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });

  testWidgets('after using the sort menu', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('sort-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.sortLabel(TaskSort.title)).last);
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });

  testWidgets('from the details editor', (tester) async {
    final notifier = await _pump(tester);
    notifier.selectTask('a');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notes-a')));
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });

  testWidgets('from the Dashboard it returns to the list and focuses search', (
    tester,
  ) async {
    final notifier = await _pump(tester);
    notifier.selectDashboard();
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    // The dashboard has no search field; the key must not do nothing silently.
    expect(_search, findsOneWidget);
    await _expectTypingWorks(tester);
  });

  testWidgets('with the overlay layout (1000 px)', (tester) async {
    final notifier = await _pump(tester, w: 1000);
    notifier.selectTask('a');
    await tester.pumpAndSettle();
    await _ctrlF(tester);
    await _expectTypingWorks(tester);
  });
}
