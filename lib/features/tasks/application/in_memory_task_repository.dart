import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_deletion.dart';

import 'repository_exception.dart';
import 'task_repository.dart';

/// Phase 1 storage. Data lives only as long as the process.
final class InMemoryTaskRepository implements TaskRepository, ProjectStore {
  InMemoryTaskRepository({
    required List<Project> projects,
    required List<Task> tasks,
  }) : _projects = List<Project>.of(projects),
       _tasks = {for (final task in tasks) task.id: task};

  final List<Project> _projects;
  final Map<String, Task> _tasks;
  final List<Task> _savedTasks = [];

  /// When true, the next load (of projects or tasks) throws once.
  bool failNextLoad = false;

  /// When true, the next save throws once and stores nothing.
  bool failNextSave = false;

  /// Runs inside [saveTask] before the write. Lets tests simulate a user
  /// edit arriving while a save is in flight.
  void Function()? beforeSave;

  /// Every successful save, in order.
  List<Task> get savedTasks => List<Task>.unmodifiable(_savedTasks);

  @override
  Future<List<Project>> loadProjects() async {
    _consumeLoadFailure();
    return List<Project>.of(_projects);
  }

  @override
  Future<List<Task>> loadTasks() async {
    _consumeLoadFailure();
    return List<Task>.of(_tasks.values);
  }

  @override
  Future<void> saveTask(Task task) async {
    if (failNextSave) {
      failNextSave = false;
      throw const RepositoryException('simulated save failure');
    }
    beforeSave?.call();
    _tasks[task.id] = task;
    _savedTasks.add(task);
  }

  @override
  Future<void> saveProject(Project project) async {
    if (failNextSave) {
      failNextSave = false;
      throw const RepositoryException('simulated save failure');
    }
    final index = _projects.indexWhere((p) => p.id == project.id);
    if (index < 0) {
      _projects.add(project);
    } else {
      _projects[index] = project;
    }
  }

  /// Ids removed by [deleteTaskTree] and [deleteProjectTree], in the order they
  /// were removed: children before their parent, the project last. Lets tests
  /// check the order.
  final List<String> deletedIds = [];

  /// When true the next delete throws a [RepositoryException] and changes
  /// nothing.
  bool failNextDelete = false;

  @override
  Future<void> deleteTaskTree(String taskId) async {
    _consumeDeleteFailure();
    if (!_tasks.containsKey(taskId)) {
      throw RepositoryException('no live task $taskId to delete');
    }
    for (final id in leafFirstDeletionOrder(_tasks, [taskId])) {
      _tasks.remove(id);
      deletedIds.add(id);
    }
  }

  @override
  Future<void> deleteProjectTree(String projectId) async {
    _consumeDeleteFailure();
    if (!_projects.any((project) => project.id == projectId)) {
      throw RepositoryException('no live project $projectId to delete');
    }
    for (final id in projectDeletionOrder(_tasks, projectId)) {
      _tasks.remove(id);
      deletedIds.add(id);
    }
    _projects.removeWhere((project) => project.id == projectId);
    deletedIds.add(projectId);
  }

  void _consumeDeleteFailure() {
    if (failNextDelete) {
      failNextDelete = false;
      throw const RepositoryException('simulated delete failure');
    }
  }

  void _consumeLoadFailure() {
    if (failNextLoad) {
      failNextLoad = false;
      throw const RepositoryException('simulated load failure');
    }
  }
}
