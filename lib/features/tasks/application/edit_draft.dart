import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Editable copy of one task. [base] is the last persisted snapshot.
final class EditDraft {
  const EditDraft({
    required this.base,
    required this.title,
    required this.status,
    required this.priority,
    required this.dueDate,
    required this.notes,
  });

  factory EditDraft.fromTask(Task task) {
    return EditDraft(
      base: task,
      title: task.title,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate,
      notes: task.notes,
    );
  }

  final Task base;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final CalendarDate? dueDate;
  final String notes;

  String get taskId => base.id;

  /// True when any editable field differs from [base].
  bool get isDirty {
    return title != base.title ||
        status != base.status ||
        priority != base.priority ||
        dueDate != base.dueDate ||
        notes != base.notes;
  }

  EditDraft copyWith({
    String? title,
    TaskStatus? status,
    TaskPriority? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    String? notes,
  }) {
    return EditDraft(
      base: base,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      notes: notes ?? this.notes,
    );
  }

  /// Rebases this draft after a successful save of [snapshot], the draft as it
  /// was when the save started. A field the user changed after the snapshot
  /// keeps the edited value; every other field takes the saved value.
  EditDraft rebaseAfterSave({
    required EditDraft snapshot,
    required Task savedTask,
  }) {
    return EditDraft(
      base: savedTask,
      title: title == snapshot.title ? savedTask.title : title,
      status: status == snapshot.status ? savedTask.status : status,
      priority: priority == snapshot.priority ? savedTask.priority : priority,
      dueDate: dueDate == snapshot.dueDate ? savedTask.dueDate : dueDate,
      notes: notes == snapshot.notes ? savedTask.notes : notes,
    );
  }

  /// The task as it would be stored, using the draft's fields as written.
  Task toTask() {
    return base.copyWith(
      title: title,
      status: status,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: dueDate == null,
      notes: notes,
    );
  }
}
