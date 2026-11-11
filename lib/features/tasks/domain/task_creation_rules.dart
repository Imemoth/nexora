import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/core/result.dart';

import 'project.dart';
import 'task.dart';
import 'task_status.dart';
import 'task_validation.dart';

/// Why a create request is rejected.
enum CreateError {
  titleRequired,
  titleTooLong,
  unknownProject,
  unknownParent,
  parentArchived,
  idCollision,
}

/// Creates a root task in [projectId], appended after its existing roots.
///
/// The new task is open, has no priority or due date, and has empty notes.
/// Inputs are never modified.
Result<Task, CreateError> createRootTask({
  required String title,
  required String projectId,
  required Map<String, Project> projects,
  required Iterable<Task> tasks,
  required IdGenerator ids,
}) {
  final list = tasks.toList(growable: false);
  final String validTitle;
  switch (_checkTitle(title)) {
    case Ok(:final value):
      validTitle = value;
    case Err(:final error):
      return Err<Task, CreateError>(error);
  }
  if (!projects.containsKey(projectId)) {
    return const Err<Task, CreateError>(CreateError.unknownProject);
  }
  final positions = <int>[];
  for (final task in list) {
    if (task.projectId == projectId && task.parentId == null) {
      positions.add(task.position);
    }
  }
  final id = ids.nextId();
  if (_findById(list, id) != null) {
    return const Err<Task, CreateError>(CreateError.idCollision);
  }
  final task = Task(
    id: id,
    projectId: projectId,
    title: validTitle,
    position: _nextPosition(positions),
  );
  return Ok<Task, CreateError>(task);
}

/// Creates a child of [parentId]. The child inherits the parent's project and
/// is appended after the parent's existing children.
///
/// The parent's status is never changed. Completion is derived, never stored.
Result<Task, CreateError> createSubtask({
  required String title,
  required String parentId,
  required Iterable<Task> tasks,
  required IdGenerator ids,
}) {
  final list = tasks.toList(growable: false);
  final String validTitle;
  switch (_checkTitle(title)) {
    case Ok(:final value):
      validTitle = value;
    case Err(:final error):
      return Err<Task, CreateError>(error);
  }
  final parent = _findById(list, parentId);
  if (parent == null) {
    return const Err<Task, CreateError>(CreateError.unknownParent);
  }
  if (parent.status == TaskStatus.archived) {
    return const Err<Task, CreateError>(CreateError.parentArchived);
  }
  final positions = <int>[];
  for (final task in list) {
    if (task.parentId == parentId) {
      positions.add(task.position);
    }
  }
  final id = ids.nextId();
  if (_findById(list, id) != null) {
    return const Err<Task, CreateError>(CreateError.idCollision);
  }
  final child = Task(
    id: id,
    projectId: parent.projectId,
    parentId: parentId,
    title: validTitle,
    position: _nextPosition(positions),
  );
  return Ok<Task, CreateError>(child);
}

Result<String, CreateError> _checkTitle(String raw) {
  return switch (validateTitle(raw)) {
    Ok(:final value) => Ok<String, CreateError>(value),
    Err(:final error) => Err<String, CreateError>(_titleError(error)),
  };
}

CreateError _titleError(TitleError error) {
  return switch (error) {
    TitleError.required => CreateError.titleRequired,
    TitleError.tooLong => CreateError.titleTooLong,
  };
}

Task? _findById(List<Task> list, String id) {
  for (final task in list) {
    if (task.id == id) {
      return task;
    }
  }
  return null;
}

/// One past the highest position, or 0 when there are none.
int _nextPosition(List<int> positions) {
  var next = 0;
  for (final position in positions) {
    if (position >= next) {
      next = position + 1;
    }
  }
  return next;
}
