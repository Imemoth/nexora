import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/edit_draft.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_completion.dart';
import 'package:nexora/features/tasks/domain/task_completion_tree.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';

import 'delete_flow.dart';
import 'due_date_field.dart';
import 'keymap.dart';
import 'keyboard_actions.dart';
import 'status_badge.dart';
import 'strings/app_strings.dart';
import 'synced_text_field.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';
import 'theme/nexora_colors.dart';

/// Right pane: the editor for the selected task. Every edit goes to the
/// workspace draft. Save and Revert are enabled only for a dirty draft.
class DetailsPane extends StatelessWidget {
  const DetailsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final draft = state.draft;
    final Widget content;
    if (draft == null) {
      content = const Center(child: Text(AppStrings.selectTaskPrompt));
    } else {
      content = _TaskEditor(notifier: notifier, state: state, draft: draft);
    }
    return KeymapScope(
      inEditor: true,
      child: ColoredBox(color: NexoraColors.of(context).panel, child: content),
    );
  }
}

class _TaskEditor extends StatelessWidget {
  const _TaskEditor({
    required this.notifier,
    required this.state,
    required this.draft,
  });

  final TasksNotifier notifier;
  final WorkspaceState state;
  final EditDraft draft;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dirty = draft.isDirty;
    final error = state.error;
    final titleError = _isTitleError(error)
        ? AppStrings.errorMessage(error!)
        : null;
    final formError = error != null && !_isTitleError(error)
        ? AppStrings.errorMessage(error)
        : null;
    final canAddSubtask = draft.status != TaskStatus.archived;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (dirty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              AppStrings.unsavedIndicator,
              key: const ValueKey('dirty-indicator'),
              style: textTheme.labelLarge,
            ),
          ),
        SyncedTextField(
          key: ValueKey('title-${draft.taskId}'),
          value: draft.title,
          label: AppStrings.fieldTitle,
          errorText: titleError,
          focusNode: TaskKeyboardFocus.of(notifier).title,
          onChanged: (value) => notifier.editDraft(title: value),
        ),
        const SizedBox(height: 16),
        _LabeledDropdown<TaskStatus>(
          label: AppStrings.fieldStatus,
          fieldKey: const ValueKey('status-dropdown'),
          value: draft.status,
          values: TaskStatus.values,
          labelOf: AppStrings.statusLabel,
          onChanged: (value) => notifier.editDraft(status: value),
        ),
        const SizedBox(height: 16),
        _LabeledDropdown<TaskPriority>(
          label: AppStrings.fieldPriority,
          fieldKey: const ValueKey('priority-dropdown'),
          value: draft.priority,
          values: TaskPriority.values,
          labelOf: AppStrings.priorityLabel,
          onChanged: (value) => notifier.editDraft(priority: value),
        ),
        const SizedBox(height: 16),
        DueDateField(
          key: const ValueKey('due-date-field'),
          dueDate: draft.dueDate,
          today: state.today,
          onChanged: (date) =>
              notifier.editDraft(dueDate: date, clearDueDate: date == null),
        ),
        const SizedBox(height: 16),
        SyncedTextField(
          key: ValueKey('notes-${draft.taskId}'),
          value: draft.notes,
          label: AppStrings.fieldNotes,
          minLines: 4,
          maxLines: 8,
          onChanged: (value) => notifier.editDraft(notes: value),
        ),
        const SizedBox(height: 12),
        _ChildSummary(completion: completionOf(draft.taskId, state.tasks)),
        _SubtaskList(
          subtasks: _subtasksOf(state, draft.taskId),
          onOpen: notifier.selectTask,
        ),
        if (formError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              formError,
              key: const ValueKey('editor-error'),
              style: textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              key: const ValueKey('delete-task'),
              style: TextButton.styleFrom(
                foregroundColor: NexoraColors.of(context).statusOverdue,
              ),
              onPressed: () =>
                  deleteTaskWithConfirmation(context, notifier, draft.taskId),
              icon: const Icon(Icons.delete_outline),
              label: const Text(AppStrings.deleteTaskAction),
            ),
            TextButton(
              key: const ValueKey('add-subtask'),
              onPressed: canAddSubtask
                  ? () => openCreateTask(
                      context,
                      notifier,
                      parentId: draft.taskId,
                      parentTitle: draft.title,
                    )
                  : null,
              child: const Text(AppStrings.addSubtaskAction),
            ),
            TextButton(
              key: const ValueKey('revert'),
              onPressed: dirty ? notifier.revertDraft : null,
              child: const Text(AppStrings.revertAction),
            ),
            FilledButton(
              key: const ValueKey('save'),
              onPressed: dirty ? () => notifier.saveDraft() : null,
              child: const Text(AppStrings.saveAction),
            ),
          ],
        ),
      ],
    );
  }

  List<Task> _subtasksOf(WorkspaceState state, String parentId) {
    final children = [
      for (final task in state.tasks.values)
        if (task.parentId == parentId) task,
    ]..sort((a, b) => a.position.compareTo(b.position));
    return children;
  }

  bool _isTitleError(WorkspaceError? error) {
    return error == WorkspaceError.titleRequired ||
        error == WorkspaceError.titleTooLong;
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.fieldKey,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final Key fieldKey;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        DropdownButton<T>(
          key: fieldKey,
          isExpanded: true,
          value: value,
          items: [
            for (final option in values)
              DropdownMenuItem<T>(value: option, child: Text(labelOf(option))),
          ],
          onChanged: (selected) {
            if (selected != null) {
              onChanged(selected);
            }
          },
        ),
      ],
    );
  }
}

/// Read-only list of the selected task's direct subtasks. Tapping one selects
/// it, through the same unsaved-change gate as the task list.
class _SubtaskList extends StatelessWidget {
  const _SubtaskList({required this.subtasks, required this.onOpen});

  final List<Task> subtasks;
  final ValueChanged<String?> onOpen;

  @override
  Widget build(BuildContext context) {
    if (subtasks.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = NexoraColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      key: const ValueKey('subtask-list'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.subtasksHeader, style: textTheme.labelMedium),
          const SizedBox(height: 6),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                for (final subtask in subtasks)
                  InkWell(
                    key: ValueKey('subtask-${subtask.id}'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onOpen(subtask.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            statusStyle(colors, subtask.status).icon,
                            size: 20,
                            color: statusStyle(colors, subtask.status).color,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              subtask.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            AppStrings.statusLabel(subtask.status),
                            style: textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildSummary extends StatelessWidget {
  const _ChildSummary({required this.completion});

  final TaskCompletion completion;

  @override
  Widget build(BuildContext context) {
    if (completion.total == 0) {
      return const SizedBox.shrink();
    }
    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      key: const ValueKey('child-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.progress(completion.done, completion.total),
          style: style,
        ),
        if (completion.eligibleForReview)
          Text(AppStrings.readyForReview, style: style),
      ],
    );
  }
}
