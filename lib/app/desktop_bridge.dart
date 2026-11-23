import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/presentation/reminders_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/platform/desktop_integration.dart';

/// Connects the Windows shell (tray, notifications) to the visible app and
/// provides the reminders of the active workspace to the widgets below.
///
/// - A notification click selects the task in the current workspace.
/// - Exit from the tray menu first passes the unsaved-changes gate (Save,
///   Discard or Cancel for a dirty draft), then runs [beforeExit] (bounded by
///   [exitGrace]) and ends the process. Cancel, or a failed save, keeps the app
///   and the draft.
/// - With neither [desktop] nor [reminders] it is a pass-through.
/// Closes what must be closed ([beforeExit], bounded by [grace]) and then ends
/// the process through the native shell. A failing or hanging [beforeExit]
/// never prevents the exit: an exit that already passed the gate must end.
Future<void> finishExit(
  DesktopIntegration desktop, {
  Future<void> Function()? beforeExit,
  Duration grace = const Duration(seconds: 3),
}) async {
  try {
    await beforeExit?.call().timeout(grace);
  } on Object {
    // The process ends anyway.
  }
  await desktop.quit();
}

class DesktopBridge extends StatefulWidget {
  const DesktopBridge({
    super.key,
    required this.child,
    this.desktop,
    this.reminders,
    this.beforeExit,
    this.exitGrace = const Duration(seconds: 3),
  });

  final Widget child;
  final DesktopIntegration? desktop;
  final ReminderService? reminders;

  /// Flushes and closes the runtime before the process ends. Optional.
  final Future<void> Function()? beforeExit;
  final Duration exitGrace;

  @override
  State<DesktopBridge> createState() => _DesktopBridgeState();
}

class _DesktopBridgeState extends State<DesktopBridge> {
  StreamSubscription<DesktopEvent>? _subscription;
  RemindersNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(DesktopBridge old) {
    super.didUpdateWidget(old);
    if (old.reminders != widget.reminders) {
      _notifier?.dispose();
      _notifier = null;
      _attach(events: false);
    }
  }

  void _attach({bool events = true}) {
    final reminders = widget.reminders;
    final desktop = widget.desktop;
    if (reminders != null) {
      _notifier = RemindersNotifier(
        reminders,
        nativeAvailable: desktop?.available ?? false,
      );
    }
    if (events && desktop != null) {
      _subscription = desktop.events.listen(_onEvent);
      unawaited(desktop.ready());
    }
  }

  void _onEvent(DesktopEvent event) {
    switch (event) {
      case NotificationClicked(:final taskId):
        if (taskId != null && mounted) {
          TasksScope.of(context).revealTask(taskId);
        }
      case ExitRequested():
        unawaited(_requestExit());
      case WindowActivated():
        break;
    }
  }

  /// Tray Exit. A clean workspace exits at once. Unsaved task edits open the
  /// existing gate (the same dialog as the title-bar X) and the process ends
  /// only from its Save or Discard answer, see [NexoraApp].
  Future<void> _requestExit() async {
    final desktop = widget.desktop;
    if (desktop == null) {
      return;
    }
    final notifier = TasksScope.of(context);
    var allowed = await notifier.requestExit();
    // A save or create that is still running refuses the request without
    // opening the gate: ask again for a moment.
    for (var i = 0; !allowed && notifier.state.pending == null && i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) {
        return;
      }
      allowed = await notifier.requestExit();
    }
    if (allowed) {
      await finishExit(
        desktop,
        beforeExit: widget.beforeExit,
        grace: widget.exitGrace,
      );
    } else {
      await desktop.holdExit();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _notifier?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = _notifier;
    if (notifier == null) {
      return widget.child;
    }
    return ReminderScope(notifier: notifier, child: widget.child);
  }
}
