import 'package:flutter/material.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';

import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'theme/nexora_colors.dart';

/// Asks the user to confirm a delete. Returns true only for an explicit
/// Delete. Cancel, Esc and a tap outside all return false.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final colors = NexoraColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: Icon(Icons.delete_outline, color: colors.statusOverdue, size: 28),
      title: Text(title),
      content: Text(body, key: const ValueKey('delete-body')),
      actions: [
        TextButton(
          key: const ValueKey('delete-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStrings.cancelAction),
        ),
        FilledButton.icon(
          key: const ValueKey('delete-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.statusOverdue,
            foregroundColor: colors.onAccent,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.delete_outline),
          label: const Text(AppStrings.deleteAction),
        ),
      ],
    ),
  );
  return confirmed ?? false;
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
  _report(context, result, AppStrings.projectDeleted);
}

void _report(
  BuildContext context,
  Result<void, WorkspaceError> result,
  String successMessage,
) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = switch (result) {
    Ok() => successMessage,
    Err(:final error) => AppStrings.errorMessage(error),
  };
  messenger?.showSnackBar(SnackBar(content: Text(message)));
}
