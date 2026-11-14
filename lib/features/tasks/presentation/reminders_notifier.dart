import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';

/// Thin presentation adapter over [ReminderService]: forwards intents and
/// notifies listeners on every service change. It holds no rules.
final class RemindersNotifier extends ChangeNotifier {
  RemindersNotifier(this.service, {required this.nativeAvailable}) {
    _subscription = service.changes.listen((_) => notifyListeners());
  }

  final ReminderService service;

  /// Whether native desktop notifications are active (for the fallback hint).
  final bool nativeAvailable;
  late final StreamSubscription<void> _subscription;

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}

/// Makes the reminders of the active workspace available to the widgets. Absent
/// (null) in builds and tests that do not wire reminders: the UI then hides every
/// reminder control.
class ReminderScope extends InheritedNotifier<RemindersNotifier> {
  const ReminderScope({
    super.key,
    required RemindersNotifier super.notifier,
    required super.child,
  });

  static RemindersNotifier? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ReminderScope>()
        ?.notifier;
  }
}
