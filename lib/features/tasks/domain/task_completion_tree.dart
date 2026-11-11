import 'task.dart';
import 'task_completion.dart';
import 'task_status.dart';

/// Completion summary of [taskId]'s direct children.
///
/// Derived only. It never changes any task's status, and grandchildren are
/// not counted.
TaskCompletion completionOf(String taskId, Map<String, Task> tasks) {
  final statuses = <TaskStatus>[];
  for (final task in tasks.values) {
    if (task.parentId == taskId) {
      statuses.add(task.status);
    }
  }
  return summarizeChildren(statuses);
}
