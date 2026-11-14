import 'task.dart';

/// Ids to delete, children before parents (leaf-first), for the subtrees under
/// [rootIds].
///
/// The sync contract (D-P) requires the client to tombstone every child before
/// its parent, so the order returned here is the order the tombstones are
/// written. Ids in [rootIds] that are not in [tasks] are ignored. Each task
/// appears once.
List<String> leafFirstDeletionOrder(
  Map<String, Task> tasks,
  Iterable<String> rootIds,
) {
  final childrenOf = <String, List<Task>>{};
  for (final task in tasks.values) {
    final parent = task.parentId;
    if (parent != null) {
      childrenOf.putIfAbsent(parent, () => []).add(task);
    }
  }
  for (final children in childrenOf.values) {
    children.sort((a, b) {
      final byPosition = a.position.compareTo(b.position);
      return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
    });
  }
  final ordered = <String>[];
  final seen = <String>{};
  void visit(String id) {
    if (!seen.add(id)) {
      return;
    }
    for (final child in childrenOf[id] ?? const <Task>[]) {
      visit(child.id);
    }
    ordered.add(id);
  }

  for (final id in rootIds) {
    if (tasks.containsKey(id)) {
      visit(id);
    }
  }
  return ordered;
}

/// Ids of every task in [projectId], leaf-first.
List<String> projectDeletionOrder(Map<String, Task> tasks, String projectId) {
  final roots = [
    for (final task in tasks.values)
      if (task.projectId == projectId && task.parentId == null) task.id,
  ]..sort();
  final ordered = leafFirstDeletionOrder(tasks, roots);
  // A task whose parent is missing would be skipped above; include it too so
  // deleting a project never leaves a live task behind.
  final covered = ordered.toSet();
  for (final task in tasks.values) {
    if (task.projectId == projectId && !covered.contains(task.id)) {
      ordered.add(task.id);
    }
  }
  return ordered;
}
