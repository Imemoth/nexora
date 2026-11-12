import 'task_status.dart';

/// Immutable summary of a parent task's direct children.
///
/// This is a derived projection. It is never persisted as a parent status:
/// a parent is closed only by explicit manual action.
class TaskCompletion {
  const TaskCompletion({
    required this.total,
    required this.done,
    required this.eligibleForReview,
  });

  /// Number of direct children.
  final int total;

  /// Number of direct children whose status is [TaskStatus.done].
  final int done;

  /// True only when there is at least one child and all children are done.
  /// The parent moves to review; it is not closed automatically.
  final bool eligibleForReview;
}

/// Summarizes the direct children of a parent task.
///
/// Only [TaskStatus.done] counts as complete. [TaskStatus.archived] children
/// count toward [TaskCompletion.total] but never toward [TaskCompletion.done].
TaskCompletion summarizeChildren(Iterable<TaskStatus> directChildren) {
  var total = 0;
  var done = 0;
  for (final status in directChildren) {
    total++;
    if (status == TaskStatus.done) {
      done++;
    }
  }
  return TaskCompletion(
    total: total,
    done: done,
    eligibleForReview: total > 0 && done == total,
  );
}
