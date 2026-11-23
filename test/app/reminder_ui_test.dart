import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int scheduleCalls = 0;

  @override
  Reminder? get(String id) => rows[id];
  @override
  List<Reminder> all() => rows.values.toList();
  @override
  void schedule(String id, LocalWallTime wall, DateTime now) {
    scheduleCalls++;
    rows[id] = Reminder(
      taskId: id,
      remindAt: wall,
      state: ReminderState.scheduled,
    );
  }

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
  Future<void> holdExit() async {}
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

typedef _Pumped = ({
  TasksNotifier notifier,
  ReminderService service,
  _FakeDesktop desktop,
  _Memory memory,
});

Future<_Pumped> _pump(
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
  tester.view.physicalSize = const Size(1400, 1300);
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
  return (
    notifier: notifier,
    service: service,
    desktop: desktop,
    memory: memory,
  );
}

/// Opens the reminder dialog; [custom] also switches to the custom date and
/// hour fields (the presets are the default).
Future<void> _openReminder(WidgetTester tester, {bool custom = false}) async {
  await tester.tap(find.byKey(const ValueKey('reminder-button')));
  await tester.pumpAndSettle();
  if (custom) {
    await tester.tap(find.byKey(const ValueKey('reminder-choice-custom')));
    await tester.pumpAndSettle();
  }
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
    expect(find.text(ReminderStrings.deviceTag), findsOneWidget);
    expect(
      find.textContaining(ReminderStrings.notSynchronized),
      findsOneWidget,
    );
  });

  testWidgets('without reminders wired the editor is absent', (tester) async {
    final harness = await loadedHarness(tasks: sampleTasks());
    final notifier = TasksNotifier(harness.workspace);
    tester.view.physicalSize = const Size(1400, 1300);
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

  for (final width in [1100.0, 1366.0, 1920.0]) {
    testWidgets('the strip keeps the task name and every action at '
        '${width.toInt()} px', (tester) async {
      final h = await _pump(tester);
      const longTitle =
          'Prepare the quarterly report for the regional finance meeting';
      h.memory.tasks['a'] = const ReminderTaskInfo(
        title: longTitle,
        open: true,
      );
      h.service.setReminder('a', const LocalWallTime(2026, 11, 14, 13, 0));
      (h.service.clock as FakeZoneClock).now = _noon.add(
        const Duration(hours: 1),
      );
      await tester.runAsync(h.service.tick);
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();

      final banner = tester.getRect(
        find.byKey(const ValueKey('reminder-banner')),
      );
      final title = find.descendant(
        of: find.byKey(const ValueKey('reminder-banner')),
        matching: find.text(longTitle),
      );
      expect(title, findsOneWidget);
      // The name is readable: a real width, not a sliver.
      expect(tester.getSize(title).width, greaterThan(180));
      // Every control is inside the strip and reachable.
      for (final key in [
        'reminder-open-a',
        'reminder-snooze-a',
        'reminder-done-a',
      ]) {
        final r = tester.getRect(find.byKey(ValueKey(key)));
        expect(r.left, greaterThanOrEqualTo(banner.left), reason: key);
        expect(r.right, lessThanOrEqualTo(banner.right + 0.5), reason: key);
      }
      expect(tester.takeException(), isNull);
      // The whole name is the tooltip (it can be cut at the narrowest width).
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(of: title, matching: find.byType(Tooltip)),
            )
            .message,
        longTitle,
      );
    });
  }

  testWidgets('snooze from the banner hides it until the snooze ends', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 14, 13, 0));
    final clock = h.service.clock as FakeZoneClock;
    clock.now = _noon.add(const Duration(hours: 1));
    await tester.runAsync(h.service.tick);
    await tester.pumpAndSettle();

    // Snooze is a menu on the strip (Phase 5).
    await tester.tap(find.byKey(const ValueKey('reminder-snooze-a')));
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
    await _openReminder(tester, custom: true);
    // The inline editor: today at 09:00 is before the fake noon.
    await tester.enterText(
      find.byKey(const ValueKey('reminder-date')),
      '2026-11-14',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reminder-time')),
      '09:00',
    );
    await tester.tap(find.byKey(const ValueKey('reminder-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-error')), findsOneWidget);
    // The editor stays open after the error.
    expect(find.byKey(const ValueKey('reminder-date')), findsOneWidget);
    expect(h.service.reminderFor('a'), isNull);
  });

  testWidgets('an existing reminder is shown and can be removed', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 20, 8, 30));
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        ReminderStrings.friendlyWhen(const LocalWallTime(2026, 11, 20, 8, 30)),
      ),
      findsOneWidget,
    );
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

  testWidgets(
    'reminder actions never touch the draft; Revert leaves the reminder',
    (tester) async {
      final h = await _pump(tester);
      h.notifier.selectTask('a');
      h.notifier.editDraft(title: 'Alpha edited');
      await tester.pumpAndSettle();
      expect(h.notifier.state.draft!.isDirty, isTrue);

      // set
      await _openReminder(tester, custom: true);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2026-11-20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-time')),
        '08:30',
      );
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(h.service.reminderFor('a'), isNotNull);
      expect(h.notifier.state.draft!.title, 'Alpha edited');
      expect(h.notifier.state.draft!.isDirty, isTrue);

      // change
      h.service.setReminder('a', const LocalWallTime(2026, 11, 21, 9, 0));
      await tester.pumpAndSettle();
      expect(h.notifier.state.draft!.isDirty, isTrue);

      // snooze
      h.service.snooze('a', const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(h.notifier.state.draft!.isDirty, isTrue);

      // Revert undoes the title, not the reminder.
      h.notifier.revertDraft();
      await tester.pumpAndSettle();
      expect(h.notifier.state.draft!.isDirty, isFalse);
      expect(h.service.reminderFor('a'), isNotNull);

      // remove: still no effect on a (new) dirty draft
      h.notifier.editDraft(title: 'again');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-clear')));
      await tester.pumpAndSettle();
      expect(h.service.reminderFor('a'), isNull);
      expect(h.notifier.state.draft!.isDirty, isTrue);
    },
  );

  testWidgets('the dialog makes one setReminder call with both custom values', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    await _openReminder(tester, custom: true);
    // Defaults: tomorrow at 09:00 (the fake clock is 2026-11-14 12:00 local).
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('reminder-date')))
          .controller!
          .text,
      '2026-11-15',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('reminder-time')))
          .controller!
          .text,
      '09:00',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reminder-date')),
      '2026-11-18',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reminder-time')),
      '07:45',
    );
    await tester.tap(find.byKey(const ValueKey('reminder-submit')));
    await tester.pumpAndSettle();
    expect(h.memory.scheduleCalls, 1);
    expect(
      h.service.reminderFor('a')!.remindAt,
      const LocalWallTime(2026, 11, 18, 7, 45),
    );
    // The dialog closed and a snackbar confirmed.
    expect(find.byKey(const ValueKey('reminder-dialog')), findsNothing);
    expect(find.byKey(const ValueKey('reminder-date')), findsNothing);
    expect(find.text(ReminderStrings.saved), findsOneWidget);
  });

  testWidgets('a past time shows the error, keeps the dialog open, no call', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    await _openReminder(tester, custom: true);
    await tester.enterText(
      find.byKey(const ValueKey('reminder-date')),
      '2026-11-14',
    );
    await tester.enterText(
      find.byKey(const ValueKey('reminder-time')),
      '09:00',
    );
    await tester.tap(find.byKey(const ValueKey('reminder-submit')));
    await tester.pumpAndSettle();
    expect(find.text(ReminderStrings.errorInPast), findsOneWidget);
    expect(find.byKey(const ValueKey('reminder-date')), findsOneWidget);
    expect(h.memory.scheduleCalls, 0);
  });

  testWidgets('Cancel closes the dialog without a call', (tester) async {
    final h = await _pump(tester);
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    await _openReminder(tester, custom: true);
    await tester.tap(find.byKey(const ValueKey('reminder-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reminder-dialog')), findsNothing);
    expect(h.memory.scheduleCalls, 0);
  });

  testWidgets('deleting a task cancels its reminder, subtasks included', (
    tester,
  ) async {
    final h = await _pump(tester);
    h.service.setReminder('a', const LocalWallTime(2026, 11, 20, 8, 30));
    h.notifier.selectTask('a');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-task')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('details-pane')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('delete-task')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();
    expect(h.service.reminderFor('a'), isNull);
  });

  group('the reminder dialog', () {
    // The fake clock is 2026-11-14 12:00 local (Saturday).
    Future<_Pumped> open(WidgetTester tester, {bool custom = false}) async {
      final h = await _pump(tester);
      h.notifier.selectTask('a');
      await tester.pumpAndSettle();
      await _openReminder(tester, custom: custom);
      return h;
    }

    String resolvedText(WidgetTester tester) => tester
        .widget<Text>(find.byKey(const ValueKey('reminder-resolved')))
        .data!;

    testWidgets('offers the four presets and a custom choice', (tester) async {
      await open(tester);
      expect(find.byKey(const ValueKey('reminder-dialog')), findsOneWidget);
      for (final label in [
        ReminderStrings.presetInOneHour,
        ReminderStrings.presetInTwoHours,
        ReminderStrings.presetInFiveHours,
        ReminderStrings.presetIn24Hours,
        ReminderStrings.presetCustom,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No inline editor any more.
      expect(find.byKey(const ValueKey('reminder-date')), findsNothing);
    });

    testWidgets(
      'each preset shows its concrete date and time before confirming',
      (tester) async {
        await open(tester);
        // Default: In 1 hour.
        expect(resolvedText(tester), contains('Sat 14 Nov, 13:00'));
        expect(find.text('Sat 14 Nov, 14:00'), findsOneWidget); // 2 hours
        expect(find.text('Sat 14 Nov, 17:00'), findsOneWidget); // 5 hours
        expect(find.text('Sun 15 Nov, 12:00'), findsOneWidget); // 24 hours

        await tester.tap(
          find.byKey(const ValueKey('reminder-choice-fiveHours')),
        );
        await tester.pumpAndSettle();
        expect(resolvedText(tester), contains('Sat 14 Nov, 17:00'));
        // Nothing is saved by looking.
        expect(find.byKey(const ValueKey('reminder-dialog')), findsOneWidget);
      },
    );

    testWidgets('confirming a preset makes one call with the shown time', (
      tester,
    ) async {
      final h = await open(tester);
      await tester.tap(find.byKey(const ValueKey('reminder-choice-twoHours')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();

      expect(h.memory.scheduleCalls, 1);
      expect(
        h.service.reminderFor('a')!.remindAt,
        const LocalWallTime(2026, 11, 14, 14, 0),
      );
      expect(find.byKey(const ValueKey('reminder-dialog')), findsNothing);
      expect(find.text(ReminderStrings.saved), findsOneWidget);
    });

    testWidgets('a preset that crosses midnight shows the next day', (
      tester,
    ) async {
      final h = await _pump(tester);
      (h.service.clock as FakeZoneClock).now = DateTime.utc(
        2026,
        11,
        15,
        4,
        30,
      );
      h.notifier.selectTask('a');
      await tester.pumpAndSettle();
      await _openReminder(tester);
      expect(resolvedText(tester), contains('Sun 15 Nov, 00:30'));
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(
        h.service.reminderFor('a')!.remindAt,
        const LocalWallTime(2026, 11, 15, 0, 30),
      );
    });

    testWidgets('custom date and hour: valid input saves exactly that', (
      tester,
    ) async {
      final h = await open(tester, custom: true);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2026-11-20',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-time')),
        '7:45',
      );
      await tester.pumpAndSettle();
      expect(resolvedText(tester), contains('Fri 20 Nov, 07:45'));
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(
        h.service.reminderFor('a')!.remindAt,
        const LocalWallTime(2026, 11, 20, 7, 45),
      );
    });

    testWidgets('malformed custom input is a clear error, nothing saved', (
      tester,
    ) async {
      final h = await open(tester, custom: true);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2026-02-30',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-time')),
        '09:00',
      );
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(find.text(ReminderStrings.errorFormat), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-dialog')), findsOneWidget);
      expect(h.memory.scheduleCalls, 0);
    });

    testWidgets('an empty custom field says what is missing', (tester) async {
      await open(tester, custom: true);
      await tester.enterText(find.byKey(const ValueKey('reminder-time')), '');
      await tester.pumpAndSettle();
      expect(resolvedText(tester), ReminderStrings.errorCustomIncomplete);
    });

    testWidgets('a custom time in the past is refused with a clear error', (
      tester,
    ) async {
      final h = await open(tester, custom: true);
      await tester.enterText(
        find.byKey(const ValueKey('reminder-date')),
        '2026-11-14',
      );
      await tester.enterText(
        find.byKey(const ValueKey('reminder-time')),
        '11:59',
      );
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(find.text(ReminderStrings.errorInPast), findsOneWidget);
      expect(find.byKey(const ValueKey('reminder-dialog')), findsOneWidget);
      expect(h.memory.scheduleCalls, 0);
      expect(h.service.reminderFor('a'), isNull);
    });

    testWidgets('Cancel saves nothing and keeps an existing reminder', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.service.setReminder('a', const LocalWallTime(2026, 11, 20, 8, 30));
      final callsBefore = h.memory.scheduleCalls;
      h.notifier.selectTask('a');
      await tester.pumpAndSettle();
      await _openReminder(tester);
      await tester.tap(find.byKey(const ValueKey('reminder-choice-fiveHours')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('reminder-dialog')), findsNothing);
      expect(h.memory.scheduleCalls, callsBefore);
      expect(
        h.service.reminderFor('a')!.remindAt,
        const LocalWallTime(2026, 11, 20, 8, 30),
      );
    });

    testWidgets('Escape closes the dialog without a call', (tester) async {
      final h = await open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reminder-dialog')), findsNothing);
      expect(h.memory.scheduleCalls, 0);
    });

    testWidgets('an existing reminder opens as Change, prefilled as custom', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.service.setReminder('a', const LocalWallTime(2026, 11, 20, 8, 30));
      h.notifier.selectTask('a');
      await tester.pumpAndSettle();
      await _openReminder(tester);
      expect(find.text(ReminderStrings.dialogTitleChange), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('reminder-date')))
            .controller!
            .text,
        '2026-11-20',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('reminder-time')))
            .controller!
            .text,
        '08:30',
      );
      // Choose a preset instead: it replaces the old reminder.
      await tester.tap(find.byKey(const ValueKey('reminder-choice-day')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(
        h.service.reminderFor('a')!.remindAt,
        const LocalWallTime(2026, 11, 15, 12, 0),
      );
    });

    testWidgets('the dialog says it is device-local and independent of Save', (
      tester,
    ) async {
      await open(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('reminder-dialog')),
          matching: find.text(ReminderStrings.dialogDeviceNote),
        ),
        findsOneWidget,
      );
    });

    testWidgets('setting a reminder from the dialog leaves the draft alone', (
      tester,
    ) async {
      final h = await _pump(tester);
      h.notifier.selectTask('a');
      h.notifier.editDraft(title: 'Edited');
      await tester.pumpAndSettle();
      await _openReminder(tester);
      await tester.tap(find.byKey(const ValueKey('reminder-submit')));
      await tester.pumpAndSettle();
      expect(h.service.reminderFor('a'), isNotNull);
      expect(h.notifier.state.draft!.title, 'Edited');
      expect(h.notifier.state.draft!.isDirty, isTrue);
    });
  });
}
