import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/workspace_harness.dart';

Future<Harness> _harness() => loadedHarness(tasks: sampleTasks());

/// Pumps the app at desktop width so all three panes are visible.
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

/// Sends one key press with optional Ctrl and Shift. No pointer events.
Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  }
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(key);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (control) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
  await tester.pumpAndSettle();
}

Finder _titleField(String taskId) => find.descendant(
  of: find.byKey(ValueKey('title-$taskId')),
  matching: find.byType(EditableText),
);

Finder _searchField() => find.descendant(
  of: find.byKey(const ValueKey('search-field')),
  matching: find.byType(EditableText),
);

bool _hasPrimaryFocus(WidgetTester tester, Finder editable) {
  return tester.widget<EditableText>(editable).focusNode.hasPrimaryFocus;
}

/// The dialog title, looked up inside the dialog. The list header's New task
/// button has the same text, so a page-wide text finder would match twice.
Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  group('keymap', () {
    testWidgets('Down selects the first row when nothing is selected', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);

      await _key(tester, LogicalKeyboardKey.arrowDown);

      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets('Down and Up move through the visible rows', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(harness.workspace.state.selectedTaskId, 'b');

      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(harness.workspace.state.selectedTaskId, 'a');

      await _key(tester, LogicalKeyboardKey.arrowUp);
      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets('Right expands a collapsed parent and keeps the selection', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('parent');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.arrowRight);

      expect(harness.workspace.state.expandedTaskIds, contains('parent'));
      expect(harness.workspace.state.selectedTaskId, 'parent');
    });

    testWidgets('Right on an expanded parent moves to its first child', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('parent');
      harness.workspace.toggleExpanded('parent');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(harness.workspace.state.selectedTaskId, 'child');

      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(harness.workspace.state.selectedTaskId, 'child');
    });

    testWidgets(
      'Left collapses an expanded row, then moves a child to its parent',
      (tester) async {
        final harness = await _harness();
        await _pump(tester, harness);
        harness.workspace.requestSelectTask('parent');
        harness.workspace.toggleExpanded('parent');
        await tester.pumpAndSettle();

        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(
          harness.workspace.state.expandedTaskIds,
          isNot(contains('parent')),
        );
        expect(harness.workspace.state.selectedTaskId, 'parent');

        harness.workspace.toggleExpanded('parent');
        harness.workspace.requestSelectTask('child');
        await tester.pumpAndSettle();

        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(harness.workspace.state.selectedTaskId, 'parent');
      },
    );

    testWidgets('Enter focuses the details title field', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.enter);

      expect(_hasPrimaryFocus(tester, _titleField('a')), isTrue);
    });

    testWidgets('Esc in the details editor returns focus to the list', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);

      await _key(tester, LogicalKeyboardKey.escape);

      expect(harness.workspace.state.selectedTaskId, 'a');
      expect(_hasPrimaryFocus(tester, _titleField('a')), isFalse);
      await _key(tester, LogicalKeyboardKey.arrowDown);
      expect(harness.workspace.state.selectedTaskId, 'b');
    });

    testWidgets('Esc in a non-empty search clears the query and keeps focus', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _key(tester, LogicalKeyboardKey.keyF, control: true);
      await tester.enterText(_searchField(), 'bike');
      await tester.pumpAndSettle();
      expect(harness.workspace.state.searchQuery, 'bike');

      await _key(tester, LogicalKeyboardKey.escape);

      expect(harness.workspace.state.searchQuery, '');
      expect(_hasPrimaryFocus(tester, _searchField()), isTrue);
    });

    testWidgets('a second Esc in the empty search returns focus to the list', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _key(tester, LogicalKeyboardKey.keyF, control: true);
      await tester.enterText(_searchField(), 'bike');
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.escape);

      await _key(tester, LogicalKeyboardKey.escape);

      expect(_hasPrimaryFocus(tester, _searchField()), isFalse);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'task-list');
      expect(harness.workspace.state.selectedTaskId, isNull);
    });

    testWidgets(
      'Esc in the search with a dirty draft keeps the draft and selection',
      (tester) async {
        final harness = await _harness();
        await _pump(tester, harness);
        await tester.tap(find.byKey(const ValueKey('row-a')));
        await tester.pumpAndSettle();
        await tester.enterText(_titleField('a'), 'Alpha 2');
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.keyF, control: true);
        // 'alp' still matches the dirty title, so the query does not hide the draft.
        await tester.enterText(_searchField(), 'alp');
        await tester.pumpAndSettle();

        await _key(tester, LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(harness.workspace.state.searchQuery, '');
        expect(harness.workspace.state.selectedTaskId, 'a');
        expect(harness.workspace.state.draft?.title, 'Alpha 2');
        expect(harness.workspace.state.draft?.isDirty, isTrue);
        expect(find.text(AppStrings.unsavedChangesTitle), findsNothing);
      },
    );

    testWidgets('Esc does not dismiss the unsaved-change dialog', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await tester.tap(find.byKey(const ValueKey('row-a')));
      await tester.pumpAndSettle();
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('row-b')));
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);

      await _key(tester, LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'a');
      expect(harness.workspace.state.draft?.title, 'Alpha 2');
    });

    testWidgets('Esc in the list clears the selection', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.escape);

      expect(harness.workspace.state.selectedTaskId, isNull);
    });

    testWidgets('Esc in the search field returns focus to the list', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      await _key(tester, LogicalKeyboardKey.keyF, control: true);

      await _key(tester, LogicalKeyboardKey.escape);
      await _key(tester, LogicalKeyboardKey.arrowDown);

      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets('Ctrl+F focuses the search field', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);

      await _key(tester, LogicalKeyboardKey.keyF, control: true);

      expect(_hasPrimaryFocus(tester, _searchField()), isTrue);
    });

    testWidgets('Ctrl+N opens the create task dialog', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);

      await _key(tester, LogicalKeyboardKey.keyN, control: true);

      expect(find.byKey(const ValueKey('create-title')), findsOneWidget);
      expect(_inDialog(AppStrings.newTaskTitle), findsOneWidget);
    });

    testWidgets('a successful create focuses the details title', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);

      await _key(tester, LogicalKeyboardKey.keyN, control: true);
      await tester.enterText(
        find.byKey(const ValueKey('create-title')),
        'Zeta',
      );
      await tester.tap(find.byKey(const ValueKey('create-submit')));
      await tester.pumpAndSettle();

      // Spec 5.5: after a create the details title takes focus.
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'details-title');
    });

    testWidgets('Ctrl+Shift+N opens the subtask dialog for the selected task', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('parent');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.keyN, control: true, shift: true);

      expect(_inDialog(AppStrings.newSubtaskTitle), findsOneWidget);
    });

    testWidgets('Ctrl+Shift+N does nothing for an archived task', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      harness.workspace.editDraft(status: TaskStatus.archived);
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.keyN, control: true, shift: true);

      expect(_inDialog(AppStrings.newSubtaskTitle), findsNothing);
    });

    testWidgets('Ctrl+S saves a dirty draft', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      harness.workspace.editDraft(title: 'Alpha 2');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.keyS, control: true);

      expect(harness.repository.savedTasks.single.title, 'Alpha 2');
    });

    testWidgets('Ctrl+S does nothing when the draft is clean', (tester) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.keyS, control: true);

      expect(harness.repository.savedTasks, isEmpty);
    });
  });

  group('gated keys', () {
    testWidgets('Up with a dirty draft opens the unsaved-change dialog', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('b');
      harness.workspace.editDraft(title: 'Beta 2');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.arrowUp);

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'b');
      expect(harness.workspace.state.draft?.title, 'Beta 2');
    });

    testWidgets('Esc with a dirty draft opens the unsaved-change dialog', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      harness.workspace.editDraft(title: 'Alpha 2');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.escape);

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets('focus returns to the list after the create dialog closes', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);

      await _key(tester, LogicalKeyboardKey.keyN, control: true);
      await tester.tap(find.byKey(const ValueKey('create-cancel')));
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.arrowDown);

      expect(harness.workspace.state.selectedTaskId, 'a');
    });

    testWidgets(
      'focus returns to the list after the unsaved-change dialog closes',
      (tester) async {
        final harness = await _harness();
        await _pump(tester, harness);
        harness.workspace.requestSelectTask('a');
        harness.workspace.editDraft(title: 'Alpha 2');
        await tester.pumpAndSettle();
        await _key(tester, LogicalKeyboardKey.arrowDown);

        await tester.tap(find.byKey(const ValueKey('gate-discard')));
        await tester.pumpAndSettle();
        expect(harness.workspace.state.selectedTaskId, 'b');

        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(harness.workspace.state.selectedTaskId, 'c');
      },
    );
  });

  group('text editing keys', () {
    testWidgets('typing and editing keys in the title field are not consumed', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.enter);
      await tester.enterText(_titleField('a'), 'Alpha 2');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.backspace);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.arrowLeft);

      expect(find.text(AppStrings.unsavedChangesTitle), findsNothing);
      expect(harness.workspace.state.selectedTaskId, 'a');
      expect(harness.workspace.state.draft?.title, 'Alpha ');
    });

    testWidgets('editing keys in the search field are not consumed', (
      tester,
    ) async {
      final harness = await _harness();
      await _pump(tester, harness);
      harness.workspace.requestSelectTask('a');
      await tester.pumpAndSettle();
      await _key(tester, LogicalKeyboardKey.keyF, control: true);
      await tester.enterText(_searchField(), 'Alp');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.backspace);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.arrowRight);

      expect(harness.workspace.state.searchQuery, 'Al');
      expect(harness.workspace.state.selectedTaskId, 'a');
    });
  });
}
