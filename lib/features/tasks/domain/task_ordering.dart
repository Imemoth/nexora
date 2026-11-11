import 'task.dart';
import 'task_priority.dart';

/// Sort orders offered for the task list.
enum TaskSort { position, dueDate, priority, title }

/// One row of a flattened task tree.
final class FlatTaskEntry {
  const FlatTaskEntry({
    required this.task,
    required this.depth,
    required this.hasChildren,
  });

  final Task task;
  final int depth;

  /// True when the task has children in the set that was flattened.
  final bool hasChildren;
}

/// Total order over tasks. Every branch ends with the id tie-break, so the
/// result never depends on input order.
int compareTasks(Task a, Task b, TaskSort sort) {
  return switch (sort) {
    TaskSort.position => _byPositionThenId(a, b),
    TaskSort.dueDate => _byDueDateThenPosition(a, b),
    TaskSort.priority => _byPriorityThenPosition(a, b),
    TaskSort.title => _byTitleThenId(a, b),
  };
}

/// Depth-first, deterministic flattening of [tasks].
///
/// A task whose parent is not in [tasks] is treated as a root, so filtered
/// subsets still render. Children are included only when their parent is in
/// [expandedIds]; pass null to include every level.
List<FlatTaskEntry> flattenTasks({
  required Iterable<Task> tasks,
  required TaskSort sort,
  Set<String>? expandedIds,
}) {
  final all = tasks.toList(growable: false);
  final ids = <String>{for (final task in all) task.id};
  final childrenOf = <String?, List<Task>>{};
  for (final task in all) {
    final parentInSet = task.parentId != null && ids.contains(task.parentId);
    final key = parentInSet ? task.parentId : null;
    childrenOf.putIfAbsent(key, () => <Task>[]).add(task);
  }
  final result = <FlatTaskEntry>[];
  void visit(String? parentKey, int depth) {
    final siblings = List<Task>.of(childrenOf[parentKey] ?? const <Task>[]);
    siblings.sort((a, b) => compareTasks(a, b, sort));
    for (final task in siblings) {
      final hasChildren = childrenOf.containsKey(task.id);
      result.add(
        FlatTaskEntry(task: task, depth: depth, hasChildren: hasChildren),
      );
      final expanded = expandedIds == null || expandedIds.contains(task.id);
      if (hasChildren && expanded) {
        visit(task.id, depth + 1);
      }
    }
  }

  visit(null, 0);
  return result;
}

int _byPositionThenId(Task a, Task b) {
  final byPosition = a.position.compareTo(b.position);
  if (byPosition != 0) {
    return byPosition;
  }
  return a.id.compareTo(b.id);
}

/// Tasks with a due date come first, earliest first. Undated tasks come last.
int _byDueDateThenPosition(Task a, Task b) {
  final dueA = a.dueDate;
  final dueB = b.dueDate;
  if (dueA == null && dueB == null) {
    return _byPositionThenId(a, b);
  }
  if (dueA == null) {
    return 1;
  }
  if (dueB == null) {
    return -1;
  }
  final byDate = dueA.compareTo(dueB);
  if (byDate != 0) {
    return byDate;
  }
  return _byPositionThenId(a, b);
}

int _priorityRank(TaskPriority priority) {
  return switch (priority) {
    TaskPriority.high => 0,
    TaskPriority.medium => 1,
    TaskPriority.low => 2,
    TaskPriority.none => 3,
  };
}

int _byPriorityThenPosition(Task a, Task b) {
  final rankA = _priorityRank(a.priority);
  final rankB = _priorityRank(b.priority);
  if (rankA != rankB) {
    return rankA.compareTo(rankB);
  }
  return _byPositionThenId(a, b);
}

int _byTitleThenId(Task a, Task b) {
  final titleA = a.title.trim().toLowerCase();
  final titleB = b.title.trim().toLowerCase();
  final byTitle = titleA.compareTo(titleB);
  if (byTitle != 0) {
    return byTitle;
  }
  return a.id.compareTo(b.id);
}
