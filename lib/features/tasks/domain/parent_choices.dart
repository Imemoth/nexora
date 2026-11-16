import 'task.dart';
import 'task_ordering.dart';
import 'task_status.dart';

/// One task offered as the parent of a new subtask.
final class ParentChoice {
  const ParentChoice({
    required this.task,
    required this.depth,
    required this.ancestors,
  });

  final Task task;

  /// 0 for a root task.
  final int depth;

  /// Titles of the ancestors, outermost first. Empty for a root task. Shown so
  /// two tasks with the same title can be told apart.
  final List<String> ancestors;
}

/// The tasks that may become the parent of a new subtask in [projectId], in
/// tree order (siblings by position).
///
/// Only tasks of the same project are offered: a subtask always takes its
/// parent's project, and the tree rules reject a parent in another project
/// (`validateParentChange`), so choosing a parent never moves work across
/// projects. Archived tasks cannot get subtasks and are left out; their
/// non-archived descendants stay offered with the full ancestry.
List<ParentChoice> subtaskParentChoices({
  required Iterable<Task> tasks,
  required String projectId,
}) {
  final inProject = [
    for (final task in tasks)
      if (task.projectId == projectId) task,
  ];
  final byId = {for (final task in inProject) task.id: task};
  final choices = <ParentChoice>[];
  for (final entry in flattenTasks(tasks: inProject, sort: TaskSort.position)) {
    if (entry.task.status == TaskStatus.archived) {
      continue;
    }
    final ancestors = <String>[];
    final seen = <String>{entry.task.id};
    var cursor = entry.task.parentId;
    while (cursor != null && seen.add(cursor)) {
      final parent = byId[cursor];
      if (parent == null) {
        break;
      }
      ancestors.insert(0, parent.title);
      cursor = parent.parentId;
    }
    choices.add(
      ParentChoice(task: entry.task, depth: entry.depth, ancestors: ancestors),
    );
  }
  return choices;
}
