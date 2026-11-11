import 'calendar_date.dart';
import 'task_priority.dart';
import 'task_status.dart';

/// A task in a project's tree. Immutable; change it with [copyWith].
final class Task {
  const Task({
    required this.id,
    required this.projectId,
    required this.title,
    required this.position,
    this.parentId,
    this.status = TaskStatus.open,
    this.priority = TaskPriority.none,
    this.dueDate,
    this.notes = '',
  });

  final String id;
  final String projectId;

  /// Null for root tasks.
  final String? parentId;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final CalendarDate? dueDate;
  final String notes;

  /// Order among siblings. Ties are broken by [id].
  final int position;

  Task copyWith({
    String? title,
    TaskStatus? status,
    TaskPriority? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    String? notes,
    int? position,
  }) {
    return Task(
      id: id,
      projectId: projectId,
      parentId: parentId,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      notes: notes ?? this.notes,
      position: position ?? this.position,
    );
  }
}
