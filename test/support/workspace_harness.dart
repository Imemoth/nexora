import 'package:nexora/features/tasks/application/in_memory_task_repository.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';

import 'fixed_clock.dart';
import 'sequential_id_generator.dart';
import 'task_fixtures.dart';

/// Fixed "today" used by every workspace test.
const testToday = CalendarDate(2026, 11, 12);

const testProjects = [
  Project(id: 'p1', name: 'Home', position: 0),
  Project(id: 'p2', name: 'Work', position: 1),
];

/// A workspace plus the repository spy behind it.
final class Harness {
  const Harness(this.workspace, this.repository);

  final TaskWorkspace workspace;
  final InMemoryTaskRepository repository;
}

/// Builds a workspace over [tasks], loads it, and returns it.
///
/// Ids issued by the workspace are `new-1`, `new-2`, and so on.
Future<Harness> loadedHarness({
  required List<Task> tasks,
  CalendarDate today = testToday,
  List<Project> projects = testProjects,
  bool failLoad = false,
  bool dueTimeSupported = true,
}) async {
  final repository = InMemoryTaskRepository(projects: projects, tasks: tasks);
  repository.failNextLoad = failLoad;
  final workspace = TaskWorkspace(
    repository: repository,
    clock: FixedClock(today),
    ids: SequentialIdGenerator([for (var i = 1; i <= 20; i++) 'new-$i']),
    dueTimeSupported: dueTimeSupported,
  );
  await workspace.load();
  return Harness(workspace, repository);
}

/// Small fixed data set covering every smart view and a parent with a child.
///
/// - a: Home, due today
/// - b: Home, due in two days, notes mention "offers"
/// - c: Work, no due date
/// - parent: Home, no due date; child is its only child
List<Task> sampleTasks() => [
  makeTask(id: 'a', title: 'Alpha', dueDate: testToday),
  makeTask(
    id: 'b',
    title: 'Beta',
    dueDate: testToday.addDays(2),
    notes: 'Compare two offers',
  ),
  makeTask(id: 'c', title: 'Gamma', projectId: 'p2'),
  makeTask(id: 'parent', title: 'Parent'),
  makeTask(id: 'child', title: 'Child', parentId: 'parent'),
];
