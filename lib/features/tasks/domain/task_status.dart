/// Lifecycle status of a task. Pure domain type: no Flutter or database imports.
///
/// A parent's status is never derived automatically from its children; see
/// `summarizeChildren` in `task_completion.dart` for the derived projection.
enum TaskStatus { open, inProgress, review, done, archived }
