import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_completion.dart';

/// One row in the task list, already flattened and sorted.
final class VisibleTaskRow {
  const VisibleTaskRow({
    required this.task,
    required this.depth,
    required this.hasChildren,
    required this.expanded,
    this.completion,
  });

  final Task task;
  final int depth;

  /// True when the task has children in the current list.
  final bool hasChildren;

  final bool expanded;

  /// Summary of direct children. Null when the task has none.
  final TaskCompletion? completion;
}
