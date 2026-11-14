import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:nexora/features/tasks/presentation/strings/reminder_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/platform/desktop_integration.dart';

import '../support/reminder_support.dart';
import '../support/workspace_harness.dart';

/// In-memory persistence: the SQLite store has its own tests.
final class _Memory implements ReminderPersistence {
  _Memory(this.tasks);

  final Map<String, ReminderTaskInfo> tasks;
  final Map<String, Reminder> rows = {};

  @override
  Reminder? get(String id) => rows[id];
  @override
  List<Reminder> all() => rows.values.toList();
  @override
  void schedule(String id, LocalWallTime wall, DateTime now) => rows[id] =
      Reminder(taskId: id, remindAt: wall, state: ReminderState.scheduled);
  @override
  bool cancel(String id) => rows.remove(id) != null;
  @override
  bool claim(Reminder e, DateTime now, {required bool missed}) {
    final cur = rows[e.taskId];
    if (cur == null || cur.state != ReminderState.scheduled) {
      return false;
    }
    rows[e.taskId] = Reminder(
      taskId: e.taskId,
      remindAt: cur.remindAt,
      state: ReminderState.notified,
      notifiedAtUtc: now,
      missed: missed,
    );
    return true;
  }

  @override
  bool acknowledge(String id, DateTime now) {
    final cur = rows[id];
    if (cur == null || cur.state == ReminderState.acknowledged) {
      return false;
    }
    rows[id] = Reminder(
      taskId: id,
      remindAt: cur.remindAt,
      state: ReminderState.acknowledged,
    );
    return true;
  }

  @override
  bool snooze(String id, DateTime until, DateTime now) {
    final cur = rows[id];
    if (cur == null) {
      return false;
    }
    rows[id] = Reminder(
      taskId: id,
      remindAt: cur.remindAt,
      state: ReminderState.scheduled,
      snoozeUntilUtc: until,
    );
    return true;
  }

  @override
  ReminderTaskInfo? taskInfo(String id) => tasks[id];
}

final class _FakeDesktop implements DesktopIntegration {
  final StreamController<DesktopEvent> controller =
      StreamController<DesktopEvent>.broadcast();
  bool readyCalled = false;
  bool quitCalled = false;
  final List<RecordedNotification> shown = [];

  @override
  bool get available => true;
  @override
  Stream<DesktopEvent> get events => controller.stream;
  @override
  Future<void> ready() async => readyCalled = true;
  @override
  Future<void> quit() async => quitCalled = true;
  @override
  Future<void> dispose() async {}
  @override
  Future<bool> show({
    required String? taskId,
    required String title,
    required String body,
  }) async {
    shown.add(RecordedNotification(taskId, title, body));
    return true;
  }
}

final _noon = DateTime.utc(2026, 11, 14, 17);

Future<
  ({TasksNotifier notifier, ReminderService service, _FakeDesktop desktop})
>
_pump(
  WidgetTester tester, {
  Future<void> Function()? beforeExit,
  Duration exitGrace = const Duration(seconds: 3),
}) async {
  final harness = await loadedHarness(tasks: sampleTasks());
  final memory = _Memory({
    'a': const ReminderTaskInfo(title: 'Alpha', open: true),
    'c': const ReminderTaskInfo(title: 'Gamma', open: true),
  });
  final clock = FakeZoneClock(_noon);
  final desktop = _FakeDesktop();
  final service = ReminderService(
    store: memory,
    clock: clock,
    notifier: desktop,
  );
  final notifier = TasksNotifier(harness.workspace);
  addTearDown(service.dispose);
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: notifier,
      desktop: desktop,
      reminders: service,
      beforeExit: beforeExit,
    ),
  );
  await tester.pumpAndSettle();
  return (notifier: notifier, service: service, desktop: desktop);
}

void main() {
  testWidgets('the bridge tells the native side that the app is ready', (
    tester,
  ) async {
    final h = await _pump(tester);
    expect(h.desktop.readyCalled, isTrue);
  });

  testWidgets('the details panel shows the device-only reminder editor', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-field')), findsOneWidget);
    expect(find.text(ReminderStrings.noReminder), findsOneWidget);
    // The UI states the behaviour explicitly: this device only.
    expect(find.byKey(const ValueKey('reminder-device-only')), findsOneWidget);
    expect(find.textContaining('this device only'), findsOneWidget);
  });

  testWidgets('without reminders wired the editor is absent', (tester) async {
    final harness = await loadedHarness(tasks: sampleTasks());
    final notifier = TasksNotifier(harness.workspace);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NexoraApp(notifier: notifier));
    await tester.pumpAndSettle();
    notifier.selectTask('a');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-field')), findsNothing);
    expect(find.byKey(const ValueKey('reminder-banner')), findsNothing);
  });

  testWidgets('a fired reminder shows in the banner and can be acknowledged', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 14, 13, 0));
    final clock = h.service.clock as FakeZoneClock;
    clock.now = _noon.add(const Duration(hours: 1));
    await tester.runAsync(h.service.tick);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('reminder-banner')), findsOneWidget);
    expect(find.text('Alpha'), findsWidgets);
    expect(h.desktop.shown, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('reminder-done-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-banner')), findsNothing);
  });

  testWidgets('snooze from the banner hides it until the snooze ends', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 14, 13, 0));
    final clock = h.service.clock as FakeZoneClock;
    clock.now = _noon.add(const Duration(hours: 1));
    await tester.runAsync(h.service.tick);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reminder-snooze10-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-banner')), findsNothing);

    clock.now = clock.now.add(const Duration(minutes: 11));
    await tester.runAsync(h.service.tick);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-banner')), findsOneWidget);
  });

  testWidgets('a notification click selects and shows the task', (
    tester,
  ) async {
    final h = await _pump(tester);
    expect(h.notifier.state.selectedTaskId, isNull);

    h.desktop.controller.add(const NotificationClicked('c'));
    await tester.pumpAndSettle();

    expect(h.notifier.state.selectedTaskId, 'c');
    expect(find.byKey(const ValueKey('reminder-field')), findsOneWidget);
  });

  testWidgets('a click on a summary notification changes nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    h.desktop.controller.add(const NotificationClicked(null));
    await tester.pumpAndSettle();
    expect(h.notifier.state.selectedTaskId, 'a');
  });

  testWidgets('a click for a task that is gone is ignored', (tester) async {
    final h = await _pump(tester);
    h.desktop.controller.add(const NotificationClicked('missing'));
    await tester.pumpAndSettle();
    expect(h.notifier.state.selectedTaskId, isNull);
  });

  testWidgets('tray Exit saves first, then ends the process', (tester) async {
    final order = <String>[];
    final h = await _pump(tester, beforeExit: () async => order.add('saved'));
    h.desktop.controller.add(const ExitRequested());
    await tester.pumpAndSettle();
    expect(h.desktop.quitCalled, isTrue);
    expect(order, ['saved']);
  });

  testWidgets('tray Exit still ends the process when saving hangs', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      beforeExit: () => Completer<void>().future,
      exitGrace: const Duration(milliseconds: 50),
    );
    h.desktop.controller.add(const ExitRequested());
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(h.desktop.quitCalled, isTrue);
  });

  testWidgets('tray Exit still ends the process when saving fails', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      beforeExit: () async => throw StateError('disk'),
    );
    h.desktop.controller.add(const ExitRequested());
    await tester.pumpAndSettle();
    expect(h.desktop.quitCalled, isTrue);
  });

  testWidgets('choosing a time in the past shows an error and stores nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reminder-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // date: today
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // time: 09:00, before the fake noon
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-error')), findsOneWidget);
    expect(h.service.reminderFor('a'), isNull);
  });

  testWidgets('an existing reminder is shown and can be removed', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 20, 8, 30));
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-11-20 08:30'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reminder-clear')));
    await tester.pumpAndSettle();
    expect(h.service.reminderFor('a'), isNull);
    expect(find.text(ReminderStrings.noReminder), findsOneWidget);
  });

  testWidgets('a due reminder offers acknowledge and snooze in the editor', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 14, 13, 0));
    (h.service.clock as FakeZoneClock).now = _noon.add(
      const Duration(hours: 1),
    );
    await tester.runAsync(h.service.tick);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-ack')), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-snooze')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reminder-ack')));
    await tester.pumpAndSettle();
    expect(h.service.due, isEmpty);
  });
}
