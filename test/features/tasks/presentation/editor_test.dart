import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/unsaved_changes_host.dart';

import '../../../support/workspace_harness.dart';

Future<Harness> _harness() => loadedHarness(tasks: sampleTasks());

/// Pumps the app. [exitCalls] counts platform exit requests.
Future<void> _pump(
  WidgetTester tester,
  Harness harness, {
  void Function()? onExitApp,
}) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace), onExitApp: onExitApp),
  );
  await tester.pumpAndSettle();
}

Finder _titleField(String taskId) => find.descendant(
  of: find.byKey(ValueKey('title-$taskId')),
  matching: find.byType(TextField),
);

Future<void> _selectRow(WidgetTester tester, String taskId) async {
  await tester.tap(find.byKey(ValueKey('row-$taskId')));
  await tester.pumpAndSettle();
}

bool _enabled(WidgetTester tester, String key) {
  final button = tester.widget<ButtonStyleButton>(find.byKey(ValueKey(key)));
  return button.onPressed != null;
}

void main() {
  group('editor', () {
    testWidgets('save and revert are enabled only for a dirty draft', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');

      expect(_enabled(tester, 'save'), isFalse);
      expect(_enabled(tester, 'revert'), isFalse);

      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();

      expect(_enabled(tester, 'save'), isTrue);
      expect(_enabled(tester, 'revert'), isTrue);
      expect(find.byKey(const ValueKey('dirty-indicator')), findsOneWidget);
    });

    testWidgets('revert restores the saved title', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('revert')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(ValueKey('title-a')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Alpha',
      );
      expect(_enabled(tester, 'save'), isFalse);
    });

    testWidgets('save persists the title and updates the list row', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save')));
      await tester.pumpAndSettle();

      expect(harness.repository.savedTasks.single.title, 'Alpha 2');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('row-a')),
          matching: find.text('Alpha 2'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an empty title shows the message and saves nothing', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), '   ');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('save')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.titleRequired), findsOneWidget);
      expect(harness.repository.savedTasks, isEmpty);
    });

    testWidgets('a failed save keeps the edits and shows the message', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      harness.repository.failNextSave = true;

      await tester.tap(find.byKey(const ValueKey('save')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.errorSaveFailed), findsOneWidget);
      expect(harness.workspace.state.draft?.title, 'Alpha 2');
      expect(harness.workspace.state.tasks['a']?.title, 'Alpha');
    });

    testWidgets('the status dropdown edits the draft', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');

      await tester.tap(find.byKey(const ValueKey('status-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.statusLabel(TaskStatus.done)).last);
      await tester.pumpAndSettle();

      expect(harness.workspace.state.draft?.status.name, 'done');
      expect(find.byKey(const ValueKey('dirty-indicator')), findsOneWidget);
    });

    testWidgets('clearing the due date marks the draft dirty', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');

      await tester.tap(find.byKey(const ValueKey('due-date-clear')));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.draft?.dueDate, isNull);
      expect(find.text(AppStrings.noDueDate), findsOneWidget);
    });

    testWidgets('an archived draft disables Add subtask', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'parent');
      harness.workspace.editDraft(status: TaskStatus.archived);
      await tester.pumpAndSettle();

      expect(_enabled(tester, 'add-subtask'), isFalse);
    });
  });

  group('creation', () {
    testWidgets('New task in Today reveals the undated task in its project', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await tester.tap(find.byKey(const ValueKey('nav-today')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('new-task')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('create-title')),
        'Zeta',
      );
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.taskCreated), findsOneWidget);
      expect(find.byKey(const ValueKey('row-new-1')), findsOneWidget);
      expect(harness.workspace.state.tasks['new-1']?.dueDate, isNull);
      expect(harness.workspace.state.selectedTaskId, 'new-1');
    });

    testWidgets('an empty title keeps the dialog open with the message', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);

      await tester.tap(find.byKey(const ValueKey('new-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.titleRequired), findsOneWidget);
      expect(find.byKey(const ValueKey('create-title')), findsOneWidget);
      expect(harness.workspace.state.tasks.containsKey('new-1'), isFalse);
    });

    testWidgets('Add subtask expands the parent and selects the child', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'parent');

      await tester.tap(find.byKey(const ValueKey('add-subtask')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('create-title')), 'Sub');
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('row-new-1')), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'new-1');
      expect(harness.workspace.state.expandedTaskIds, contains('parent'));
    });
  });

  group('unsaved-change dialog', () {
    testWidgets('selecting another task with a dirty draft opens the dialog', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();

      await _selectRow(tester, 'b');

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets('Cancel closes the dialog and keeps the draft', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      await _selectRow(tester, 'b');

      await tester.tap(find.byKey(const ValueKey('gate-cancel')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsNothing);
      expect(harness.workspace.state.draft?.title, 'Alpha 2');
    });

    testWidgets('Discard applies the pending selection', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      await _selectRow(tester, 'b');

      await tester.tap(find.byKey(const ValueKey('gate-discard')));
      await tester.pumpAndSettle();

      expect(harness.workspace.state.selectedTaskId, 'b');
      expect(harness.repository.savedTasks, isEmpty);
    });

    testWidgets('a failed save keeps the dialog open with the message', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      await _selectRow(tester, 'b');
      harness.repository.failNextSave = true;

      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('gate-error')), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'a');
    });
  });

  group('application exit', () {
    testWidgets('a clean workspace exits', (tester) async {
      final harness = await _harness();
      var exits = 0;
      await _pump(tester, harness, onExitApp: () => exits++);
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );

      expect(await host.handleExitRequest(), AppExitResponse.exit);
      expect(exits, 0);
    });

    testWidgets('a dirty workspace cancels the exit and opens the dialog', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );

      expect(await host.handleExitRequest(), AppExitResponse.cancel);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
    });

    testWidgets('Save and exit saves and then exits', (tester) async {
      final harness = await _harness();
      var exits = 0;
      await _pump(tester, harness, onExitApp: () => exits++);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );
      await host.handleExitRequest();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();

      expect(harness.repository.savedTasks.single.title, 'Alpha 2');
      expect(exits, 1);
    });

    testWidgets('Discard and exit exits without saving', (tester) async {
      final harness = await _harness();
      var exits = 0;
      await _pump(tester, harness, onExitApp: () => exits++);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );
      await host.handleExitRequest();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-discard')));
      await tester.pumpAndSettle();

      expect(harness.repository.savedTasks, isEmpty);
      expect(exits, 1);
    });

    testWidgets('Cancel keeps the application open', (tester) async {
      final harness = await _harness();
      var exits = 0;
      await _pump(tester, harness, onExitApp: () => exits++);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );
      await host.handleExitRequest();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-cancel')));
      await tester.pumpAndSettle();

      expect(exits, 0);
      expect(harness.workspace.state.draft?.title, 'Alpha 2');
    });

    testWidgets('a failed save during exit does not exit', (tester) async {
      final harness = await _harness();
      var exits = 0;
      await _pump(tester, harness, onExitApp: () => exits++);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );
      await host.handleExitRequest();
      await tester.pumpAndSettle();
      harness.repository.failNextSave = true;

      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();

      expect(exits, 0);
      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
    });

    testWidgets('repeated exit requests keep one dialog open', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _selectRow(tester, 'a');
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      final host = tester.state<UnsavedChangesHostState>(
        find.byType(UnsavedChangesHost),
      );

      await host.handleExitRequest();
      await host.handleExitRequest();
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
    });
  });
}
