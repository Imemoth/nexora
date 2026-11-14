import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';

/// The persistence boundary of the workspace. Implementations throw
/// `RepositoryException` when a call cannot complete.
abstract interface class TaskRepository {
  Future<List<Project>> loadProjects();

  Future<List<Task>> loadTasks();

  Future<void> saveTask(Task task);

  /// Deletes the tasks in [taskIdsLeafFirst], in that order, all or nothing.
  /// Children must come before their parent (sync decision D-P). Deletes are
  /// soft: rows are kept as tombstones and cannot be restored (D-T, D-E).
  Future<void> deleteTasks(List<String> taskIdsLeafFirst);

  /// Deletes a project and, first, its tasks in [taskIdsLeafFirst], all or
  /// nothing. Fails, and changes nothing, if the project still has a live task
  /// that is not in the list.
  Future<void> deleteProject(String projectId, List<String> taskIdsLeafFirst);
}
