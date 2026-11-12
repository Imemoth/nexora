import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';

import 'repository_exception.dart';
import 'task_repository.dart';

/// Phase 1 storage. Data lives only as long as the process.
final class InMemoryTaskRepository implements TaskRepository {
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
    _tasks[task.id] = task;
    _savedTasks.add(task);
  }

  void _consumeLoadFailure() {
    if (failNextLoad) {
      failNextLoad = false;
      throw const RepositoryException('simulated load failure');
    }
  }
}
