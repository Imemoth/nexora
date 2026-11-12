import 'package:flutter/widgets.dart';

import 'tasks_notifier.dart';

/// Makes the [TasksNotifier] available to the widget tree.
class TasksScope extends InheritedNotifier<TasksNotifier> {
  const TasksScope({
    super.key,
    required TasksNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static TasksNotifier of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<TasksScope>();
    if (scope == null) {
      throw StateError('TasksScope is missing above this widget');
    }
    return scope.notifier!;
  }
}
