import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';

/// Async storage contract for projects and tasks.
///
/// Phase 2 replaces the in-memory implementation with SQLite without changing
/// the workspace or the UI.
abstract interface class TaskRepository {
  Future<List<Project>> loadProjects();

  Future<List<Task>> loadTasks();

  /// Inserts or replaces the task with the same id.
  ///
  /// Throws `RepositoryException` when the write cannot complete.
  Future<void> saveTask(Task task);
}

/// Optional capability: a repository that can store a new project. The workspace
/// offers "New project" only when its repository has it.
abstract interface class ProjectStore {
  Future<void> saveProject(Project project);
}
