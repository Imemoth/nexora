import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/platform/desktop_integration.dart';

import '../support/workspace_harness.dart';

/// Regression for the Windows finding "unsaved Notes are lost on exit": both
/// ways of leaving the application must stop at the unsaved-changes gate.
///
/// - the title-bar X reaches Dart as the platform exit request
///   (`WidgetsBinding.handleRequestAppExit`, the call Flutter's Windows engine
///   makes for WM_CLOSE);
/// - tray Exit reaches Dart as [ExitRequested].
///
/// The earlier tests called `UnsavedChangesHostState.handleExitRequest`
/// directly, which never proved the host is registered with the binding.
final class _FakeDesktop implements DesktopIntegration {
  final StreamController<DesktopEvent> controller =
      StreamController<DesktopEvent>.broadcast();
  int quitCalls = 0;
  int holdCalls = 0;

  @override
  bool get available => true;
  @override
  Stream<DesktopEvent> get events => controller.stream;
  @override
  Future<void> ready() async {}
  @override
  Future<void> quit() async => quitCalls++;
  @override
  Future<void> holdExit() async => holdCalls++;
  @override
  Future<void> dispose() async {}
  @override
  Future<bool> show({
    required String? taskId,
    required String title,
    required String body,
  }) async => false;
}

typedef _Pumped = ({Harness harness, _FakeDesktop desktop, List<String> order});

Future<_Pumped> _pump(WidgetTester tester) async {
  final harness = await loadedHarness(tasks: sampleTasks());
  final desktop = _FakeDesktop();
  final order = <String>[];
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: TasksNotifier(harness.workspace),
      desktop: desktop,
      // Production wires AppHost's runtime.dispose here.
      beforeExit: () async => order.add('closed'),
    ),
  );
  await tester.pumpAndSettle();
  return (harness: harness, desktop: desktop, order: order);
}

Finder _field(String key, String taskId) => find.descendant(
  of: find.byKey(ValueKey('$key-$taskId')),
  matching: find.byType(TextField),
);

/// Selects task `a` and edits its Notes without saving.
Future<void> _editNotes(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('row-a')));
  await tester.pumpAndSettle();
  await tester.enterText(_field('notes', 'a'), 'unsaved note');
  await tester.pumpAndSettle();
}

bool _gateOpen() =>
    find.text(AppStrings.unsavedChangesTitle).evaluate().isNotEmpty;

void main() {
  group('title-bar X (platform exit request)', () {
    testWidgets('a clean workspace may exit', (tester) async {
      await _pump(tester);
      final response = await tester.binding.handleRequestAppExit();
      expect(response, AppExitResponse.exit);
      expect(_gateOpen(), isFalse);
    });

    testWidgets('unsaved Notes cancel the exit and open the gate', (
      tester,
    ) async {
      final p = await _pump(tester);
      await _editNotes(tester);

      final response = await tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();

      expect(response, AppExitResponse.cancel);
      expect(_gateOpen(), isTrue);
      expect(p.harness.workspace.state.draft?.notes, 'unsaved note');
    });

    testWidgets('unsaved changes in the other draft fields are protected too', (
      tester,
    ) async {
      final p = await _pump(tester);
      await tester.tap(find.byKey(const ValueKey('row-a')));
      await tester.pumpAndSettle();
      await tester.enterText(_field('title', 'a'), 'Alpha 2');
      await tester.pumpAndSettle();

      expect(
        await tester.binding.handleRequestAppExit(),
        AppExitResponse.cancel,
      );
      expect(p.harness.workspace.state.draft?.title, 'Alpha 2');
    });
  });

  group('tray Exit', () {
    testWidgets('a clean workspace closes and quits without a prompt', (
      tester,
    ) async {
      final p = await _pump(tester);
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();
      expect(_gateOpen(), isFalse);
      expect(p.order, ['closed']);
      expect(p.desktop.quitCalls, 1);
    });

    testWidgets('unsaved Notes stop the exit at the gate', (tester) async {
      final p = await _pump(tester);
      await _editNotes(tester);

      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();

      expect(_gateOpen(), isTrue);
      expect(p.desktop.quitCalls, 0);
      expect(p.order, isEmpty, reason: 'the runtime must stay open');
      // The window must be shown and the native forced-quit timer stopped.
      expect(p.desktop.holdCalls, 1);
    });

    testWidgets('a second Exit while the gate is open does not stack prompts', (
      tester,
    ) async {
      final p = await _pump(tester);
      await _editNotes(tester);
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.unsavedChangesTitle), findsOneWidget);
      expect(p.desktop.quitCalls, 0);
    });

    testWidgets('Save saves, then closes and quits', (tester) async {
      final p = await _pump(tester);
      await _editNotes(tester);
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();

      expect(p.harness.repository.savedTasks.single.notes, 'unsaved note');
      expect(p.order, ['closed']);
      expect(p.desktop.quitCalls, 1);
    });

    testWidgets('Discard quits without saving', (tester) async {
      final p = await _pump(tester);
      await _editNotes(tester);
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-discard')));
      await tester.pumpAndSettle();

      expect(p.harness.repository.savedTasks, isEmpty);
      expect(p.desktop.quitCalls, 1);
    });

    testWidgets('Cancel keeps the app open and the draft intact', (
      tester,
    ) async {
      final p = await _pump(tester);
      await _editNotes(tester);
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-cancel')));
      await tester.pumpAndSettle();

      expect(_gateOpen(), isFalse);
      expect(p.desktop.quitCalls, 0);
      expect(p.harness.workspace.state.draft?.notes, 'unsaved note');
      expect(p.harness.repository.savedTasks, isEmpty);
    });

    testWidgets('a failed save keeps the draft and does not quit', (
      tester,
    ) async {
      final p = await _pump(tester);
      await _editNotes(tester);
      p.desktop.controller.add(const ExitRequested());
      await tester.pumpAndSettle();
      p.harness.repository.failNextSave = true;

      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();

      expect(p.desktop.quitCalls, 0);
      expect(p.order, isEmpty);
      expect(find.byKey(const ValueKey('gate-error')), findsOneWidget);
      expect(p.harness.workspace.state.draft?.notes, 'unsaved note');

      // The user can retry and the retry succeeds.
      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();
      expect(p.desktop.quitCalls, 1);
    });
  });

  group('title-bar X then dialog, with the native shell present', () {
    testWidgets('Save closes the runtime and quits through the shell', (
      tester,
    ) async {
      final p = await _pump(tester);
      await _editNotes(tester);
      expect(
        await tester.binding.handleRequestAppExit(),
        AppExitResponse.cancel,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('gate-save')));
      await tester.pumpAndSettle();

      expect(p.harness.repository.savedTasks.single.notes, 'unsaved note');
      expect(p.order, ['closed']);
      expect(p.desktop.quitCalls, 1);
    });
  });
}
