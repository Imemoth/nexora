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
/// - Exit from the tray menu runs [beforeExit] (bounded by [exitGrace]) and then
///   ends the process.
/// - With neither [desktop] nor [reminders] it is a pass-through.
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
        unawaited(_exit());
      case WindowActivated():
        break;
    }
  }

  Future<void> _exit() async {
    try {
      await widget.beforeExit?.call().timeout(widget.exitGrace);
    } on Object {
      // The process ends anyway: an explicit Exit must always terminate.
    }
    await widget.desktop?.quit();
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
