import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';

/// The persistence boundary of the workspace. Implementations throw
/// `RepositoryException` when a call cannot complete.
abstract interface class TaskRepository {
  Future<List<Project>> loadProjects();

  Future<List<Task>> loadTasks();

  Future<void> saveTask(Task task);

  /// Deletes the task and every live descendant in one write, all or nothing.
  /// Deletes are soft: rows are kept as tombstones and cannot be restored (D-T,
  /// D-E). For a synchronized task the repository records one atomic tree
  /// delete, so the server never sees a half-deleted tree.
  Future<void> deleteTaskTree(String taskId);

  /// Deletes the project and all its live tasks in one write, all or nothing,
  /// like [deleteTaskTree].
  Future<void> deleteProjectTree(String projectId);
}

/// Optional capability: a repository that can store a new project. The workspace
/// offers "New project" only when its repository has it.
abstract interface class ProjectStore {
  Future<void> saveProject(Project project);
}
