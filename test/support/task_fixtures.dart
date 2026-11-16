import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

Task makeTask({
  required String id,
  String projectId = 'p1',
  String? parentId,
  String title = 'Task',
  TaskStatus status = TaskStatus.open,
  TaskPriority priority = TaskPriority.none,
  CalendarDate? dueDate,
  DueTime? dueTime,
  String notes = '',
  int position = 0,
}) {
  return Task(
    id: id,
    projectId: projectId,
    parentId: parentId,
    title: title,
    status: status,
    priority: priority,
    dueDate: dueDate,
    dueTime: dueTime,
    notes: notes,
    position: position,
  );
}

Map<String, Task> byId(Iterable<Task> tasks) {
  return {for (final task in tasks) task.id: task};
}
