import 'package:nexora/core/result.dart';

import 'task.dart';

/// Why a proposed parent change is rejected.
enum ParentChangeError {
  missingTask,
  missingParent,
  selfParent,
  crossProject,
  cycle,
}

Result<void, ParentChangeError> _err(ParentChangeError error) {
  return Err<void, ParentChangeError>(error);
}

/// Checks that [taskId] may be placed under [newParentId]. Null means root.
///
/// Rejects unknown tasks or parents, self-parenting, a parent in another
/// project, and any parent chain that leads back to [taskId].
Result<void, ParentChangeError> validateParentChange({
  required Map<String, Task> tasks,
  required String taskId,
  required String? newParentId,
}) {
  final task = tasks[taskId];
  if (task == null) {
    return _err(ParentChangeError.missingTask);
  }
  if (newParentId == null) {
    return const Ok<void, ParentChangeError>(null);
  }
  if (newParentId == taskId) {
    return _err(ParentChangeError.selfParent);
  }
  final parent = tasks[newParentId];
  if (parent == null) {
    return _err(ParentChangeError.missingParent);
  }
  if (parent.projectId != task.projectId) {
    return _err(ParentChangeError.crossProject);
  }
  if (_leadsBackTo(taskId, newParentId, tasks)) {
    return _err(ParentChangeError.cycle);
  }
  return const Ok<void, ParentChangeError>(null);
}

/// Walks up the parent chain from [start]. Returns true if [target] is found.
///
/// A revisited id means the stored data already loops. That is reported as a
/// cycle so the walk always terminates.
bool _leadsBackTo(String target, String start, Map<String, Task> tasks) {
  final visited = <String>{};
  String? cursor = start;
  while (cursor != null) {
    if (cursor == target) {
      return true;
    }
    if (!visited.add(cursor)) {
      return true;
    }
    cursor = tasks[cursor]?.parentId;
  }
  return false;
}
