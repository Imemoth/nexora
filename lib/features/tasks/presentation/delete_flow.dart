import 'package:flutter/material.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';

import 'reminders_notifier.dart';
import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';
import 'theme/nexora_colors.dart';

/// Asks the user to confirm a delete. Cancel has the initial focus; the
/// destructive button is outlined in the overdue colour. Returns true only for
/// an explicit Delete (Cancel, Esc and a tap outside return false).
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final c = NexoraColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('delete-dialog'),
      title: Text(title),
      content: Text(body, key: const ValueKey('delete-body')),
      actions: [
        FilledButton(
          key: const ValueKey('delete-cancel'),
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStrings.cancelAction),
        ),
        OutlinedButton(
          key: const ValueKey('delete-confirm'),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.statusOverdue,
            side: BorderSide(color: c.statusOverdue),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStrings.deleteAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A deleted task's device-local reminder is cancelled, with those of its
/// subtasks, so nothing can fire for a task that no longer exists.
void _cancelReminders(BuildContext context, List<String> taskIds) {
  final reminders = ReminderScope.maybeOf(context)?.service;
  if (reminders == null) {
    return;
  }
  for (final id in taskIds) {
    reminders.cancel(id);
  }
}

/// Confirms, then deletes the task and its subtasks. A failure is shown in a
/// snackbar and leaves everything as it was.
Future<void> deleteTaskWithConfirmation(
  BuildContext context,
  TasksNotifier notifier,
  String taskId,
) async {
  final subtasks = notifier.subtaskCountOf(taskId);
  final confirmed = await confirmDelete(
    context,
    title: AppStrings.deleteTaskTitle,
    body: AppStrings.deleteTaskBody(subtasks),
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final result = await notifier.deleteTask(taskId);
  if (!context.mounted) {
    return;
  }
  if (result case Ok(:final value)) {
    _cancelReminders(context, value);
  }
  _report(context, result, AppStrings.taskDeleted);
}

/// Confirms, then deletes the project and all its tasks.
Future<void> deleteProjectWithConfirmation(
  BuildContext context,
  TasksNotifier notifier,
  String projectId,
) async {
  final tasks = notifier.taskCountInProject(projectId);
  final confirmed = await confirmDelete(
    context,
    title: AppStrings.deleteProjectTitle,
    body: AppStrings.deleteProjectBody(tasks),
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final result = await notifier.deleteProject(projectId);
  if (!context.mounted) {
    return;
  }
  if (result case Ok(:final value)) {
    _cancelReminders(context, value);
  }
  _report(context, result, AppStrings.projectDeleted);
}

void _report(
  BuildContext context,
  Result<List<String>, WorkspaceError> result,
  String successMessage,
) {
  final message = switch (result) {
    Ok() => successMessage,
    Err(:final error) => AppStrings.errorMessage(error),
  };
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

/// "Delete task": a text button in the overdue colour at the end of the details
/// pane. There is no keyboard shortcut for delete.
class DeleteTaskButton extends StatelessWidget {
  const DeleteTaskButton({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return TextButton.icon(
      key: const ValueKey('delete-task'),
      onPressed: () =>
          deleteTaskWithConfirmation(context, TasksScope.of(context), taskId),
      style: TextButton.styleFrom(foregroundColor: c.statusOverdue),
      icon: const Icon(Icons.delete_outline, size: 18),
      label: const Text(AppStrings.deleteTaskAction),
    );
  }
}
