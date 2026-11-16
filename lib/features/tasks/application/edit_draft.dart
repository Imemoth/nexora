import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
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
    required this.dueTime,
    required this.notes,
  });

  factory EditDraft.fromTask(Task task) {
    return EditDraft(
      base: task,
      title: task.title,
      status: task.status,
      priority: task.priority,
      dueDate: task.dueDate,
      dueTime: task.dueTime,
      notes: task.notes,
    );
  }

  final Task base;
  final String title;
  final TaskStatus status;
  final TaskPriority priority;
  final CalendarDate? dueDate;
  final DueTime? dueTime;
  final String notes;

  String get taskId => base.id;

  /// True when any editable field differs from [base].
  bool get isDirty {
    return title != base.title ||
        status != base.status ||
        priority != base.priority ||
        dueDate != base.dueDate ||
        dueTime != base.dueTime ||
        notes != base.notes;
  }

  EditDraft copyWith({
    String? title,
    TaskStatus? status,
    TaskPriority? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    DueTime? dueTime,
    bool clearDueTime = false,
    String? notes,
  }) {
    final date = clearDueDate ? null : (dueDate ?? this.dueDate);
    // Clearing the date clears the time. Clearing the time keeps the date.
    final time = (clearDueDate || clearDueTime || date == null)
        ? null
        : (dueTime ?? this.dueTime);
    return EditDraft(
      base: base,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      dueDate: date,
      dueTime: time,
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
      dueTime: dueTime == snapshot.dueTime ? savedTask.dueTime : dueTime,
      notes: notes == snapshot.notes ? savedTask.notes : notes,
    );
  }

  /// Rebases this draft onto [incoming], a newer stored version of the same
  /// task that arrived from synchronization. Never discards an edit:
  ///
  /// * a field the user did not touch (draft equals [base]) takes the incoming
  ///   value;
  /// * a field the user changed keeps the user's value. When the incoming value
  ///   also differs from [base], the field is reported in
  ///   [IncomingMerge.overlap]: the user's value will replace the incoming one
  ///   if saved, and Revert loads the incoming one.
  IncomingMerge mergeIncoming(Task incoming) {
    final overlap = <String>{};
    T pick<T>(String name, T mine, T baseValue, T theirs) {
      if (mine == baseValue) {
        return theirs;
      }
      if (theirs != baseValue && theirs != mine) {
        overlap.add(name);
      }
      return mine;
    }

    final date = pick<CalendarDate?>(
      'dueDate',
      dueDate,
      base.dueDate,
      incoming.dueDate,
    );
    var time = pick<DueTime?>(
      'dueTime',
      dueTime,
      base.dueTime,
      incoming.dueTime,
    );
    if (date == null) {
      time = null;
    }
    final merged = EditDraft(
      base: incoming,
      title: pick('title', title, base.title, incoming.title),
      status: pick('status', status, base.status, incoming.status),
      priority: pick('priority', priority, base.priority, incoming.priority),
      dueDate: date,
      dueTime: time,
      notes: pick('notes', notes, base.notes, incoming.notes),
    );
    return IncomingMerge(merged, overlap);
  }

  /// The task as it would be stored, using the draft's fields as written.
  Task toTask() {
    return base.copyWith(
      title: title,
      status: status,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: dueDate == null,
      dueTime: dueTime,
      clearDueTime: dueTime == null,
      notes: notes,
    );
  }
}

/// Outcome of [EditDraft.mergeIncoming].
final class IncomingMerge {
  const IncomingMerge(this.draft, this.overlap);

  final EditDraft draft;

  /// Names of fields the user edited and that also changed incoming.
  final Set<String> overlap;
}
