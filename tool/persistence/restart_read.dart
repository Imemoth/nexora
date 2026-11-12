import 'dart:io';

import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_storage.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Process 2 of the cross-process restart check. A new process reads the same
/// database file back and checks every field written by process 1.
Future<void> main() async {
  final path = localDatabasePath(Platform.environment);
  final db = LocalDatabase.open(path);
  final repo = SqliteTaskRepository(db, ownerId: 'restart-check');
  final tasks = await repo.loadTasks();
  final projects = await repo.loadProjects();
  db.close();

  final matches = tasks.where((task) => task.id == 't1');
  final projectFound = projects.any((project) => project.id == 'p1');
  if (matches.isEmpty || !projectFound) {
    stdout.writeln('RESTART_MISSING path=$path');
    exitCode = 1;
    return;
  }
  final task = matches.single;
  final ok =
      task.title == 'Survives restart' &&
      task.status == TaskStatus.inProgress &&
      task.priority == TaskPriority.high &&
      task.notes == 'written by process 1';
  stdout.writeln(
    ok
        ? 'RESTART_OK path=$path'
        : 'RESTART_MISMATCH title=${task.title} status=${task.status} '
              'priority=${task.priority}',
  );
  exitCode = ok ? 0 : 1;
}
