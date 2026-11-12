import 'dart:io';

import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_storage.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Process 1 of the cross-process restart check. Writes one committed project and
/// task to the database named by NEXORA_DB_PATH, then exits. See restart_check.ps1.
Future<void> main() async {
  final path = localDatabasePath(Platform.environment);
  final db = LocalDatabase.open(path);
  final repo = SqliteTaskRepository(db, ownerId: 'restart-check');
  await repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
  await repo.saveTask(
    Task(
      id: 't1',
      projectId: 'p1',
      parentId: null,
      title: 'Survives restart',
      status: TaskStatus.inProgress,
      priority: TaskPriority.high,
      dueDate: null,
      notes: 'written by process 1',
      position: 0,
    ),
  );
  db.close();
  stdout.writeln('WRITE_OK path=$path');
}
