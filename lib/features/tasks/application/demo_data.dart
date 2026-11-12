import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Projects and tasks shown on first launch in Phase 1.
final class DemoData {
  const DemoData({required this.projects, required this.tasks});

  final List<Project> projects;
  final List<Task> tasks;
}

/// Deterministic demo content. Due dates are offsets from [today], so the same
/// date always produces the same data.
DemoData buildDemoData(CalendarDate today) {
  CalendarDate offset(int days) => today.addDays(days);

  return DemoData(
    projects: const [
      Project(id: 'project-home', name: 'Home', position: 0),
      Project(id: 'project-work', name: 'Work', position: 1),
    ],
    tasks: [
      Task(
        id: 'home-groceries',
        projectId: 'project-home',
        title: 'Plan weekend groceries',
        position: 0,
        dueDate: today,
        priority: TaskPriority.medium,
      ),
      Task(
        id: 'home-utility',
        projectId: 'project-home',
        title: 'Pay utility bill',
        position: 1,
        dueDate: offset(-2),
        priority: TaskPriority.high,
      ),
      Task(
        id: 'home-insurance',
        projectId: 'project-home',
        title: 'Renew car insurance',
        position: 2,
        dueDate: offset(5),
        notes: 'Compare two offers before the deadline.',
      ),
      Task(
        id: 'home-bike',
        projectId: 'project-home',
        title: 'Repair bike',
        position: 3,
        status: TaskStatus.done,
      ),
      Task(
        id: 'home-trip',
        projectId: 'project-home',
        title: 'Plan spring trip',
        position: 4,
        priority: TaskPriority.low,
      ),
      Task(
        id: 'home-trip-train',
        projectId: 'project-home',
        parentId: 'home-trip',
        title: 'Book train tickets',
        position: 0,
        status: TaskStatus.done,
      ),
      Task(
        id: 'home-trip-bags',
        projectId: 'project-home',
        parentId: 'home-trip',
        title: 'Pack bags',
        position: 1,
        dueDate: offset(9),
      ),
      Task(
        id: 'work-review',
        projectId: 'project-work',
        title: 'Quarterly review',
        position: 0,
        dueDate: offset(3),
        priority: TaskPriority.high,
      ),
      Task(
        id: 'work-metrics',
        projectId: 'project-work',
        parentId: 'work-review',
        title: 'Collect metrics',
        position: 0,
        status: TaskStatus.done,
      ),
      Task(
        id: 'work-slides',
        projectId: 'project-work',
        parentId: 'work-review',
        title: 'Draft slides',
        position: 1,
        status: TaskStatus.inProgress,
      ),
      Task(
        id: 'work-client',
        projectId: 'project-work',
        title: 'Reply to client email',
        position: 1,
        dueDate: offset(-1),
        priority: TaskPriority.medium,
      ),
      Task(
        id: 'work-archive',
        projectId: 'project-work',
        title: "Archive last year's project",
        position: 2,
        status: TaskStatus.archived,
      ),
    ],
  );
}
