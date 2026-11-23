import 'calendar_date.dart';
import 'due_time.dart';
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
    this.dueTime,
    this.notes = '',
  }) : assert(
         dueTime == null || dueDate != null,
         'a due time needs a due date',
       );

  final String id;
  final String projectId;

  /// Null for root tasks.
  final String? parentId;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final CalendarDate? dueDate;

  /// Optional wall-clock time of the deadline. Null for a date-only deadline,
  /// which is a real state: no time is implied (not midnight). Never set
  /// without [dueDate].
  final DueTime? dueTime;
  final String notes;

  /// Order among siblings. Ties are broken by [id].
  final int position;

  Task copyWith({
    String? title,
    TaskStatus? status,
    TaskPriority? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    DueTime? dueTime,
    bool clearDueTime = false,
    String? notes,
    int? position,
  }) {
    final date = clearDueDate ? null : (dueDate ?? this.dueDate);
    // Clearing the date clears the time; clearing only the time keeps the date.
    final time = (clearDueDate || clearDueTime || date == null)
        ? null
        : (dueTime ?? this.dueTime);
    return Task(
      id: id,
      projectId: projectId,
      parentId: parentId,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: date,
      dueTime: time,
      notes: notes ?? this.notes,
      position: position ?? this.position,
    );
  }
}
