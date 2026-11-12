import 'package:flutter/material.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/app/system_clock.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/in_memory_task_repository.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

/// Phase 1 wiring: deterministic in-memory demo data, no persistence.
Future<void> main() async {
  const clock = SystemClock();
  final demo = buildDemoData(clock.today());
  final repository = InMemoryTaskRepository(
    projects: demo.projects,
    tasks: demo.tasks,
  );
  final workspace = TaskWorkspace(
    repository: repository,
    clock: clock,
    ids: RandomIdGenerator(),
  );
  await workspace.load();
  runApp(NexoraApp(notifier: TasksNotifier(workspace)));
}
