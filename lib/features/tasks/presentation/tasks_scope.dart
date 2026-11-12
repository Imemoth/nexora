import 'package:flutter/widgets.dart';

import 'tasks_notifier.dart';

/// Makes the [TasksNotifier] available to the widget tree.
class TasksScope extends InheritedNotifier<TasksNotifier> {
  TasksScope({
    super.key,
    required TasksNotifier notifier,
    required Widget child,
  }) : super(notifier: notifier, child: child);

  static TasksNotifier of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TasksScope>();
    if (scope == null) {
      throw StateError('TasksScope is missing above this widget');
    }
    return scope.notifier!;
  }
}
