import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/edit_draft.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/task_completion.dart';
import 'package:nexora/features/tasks/domain/task_completion_tree.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';

import 'create_task_dialog.dart';
import 'due_date_field.dart';
import 'strings/app_strings.dart';
import 'synced_text_field.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';

/// Right pane: the editor for the selected task. Every edit goes to the
/// workspace draft. Save and Revert are enabled only for a dirty draft.
class DetailsPane extends StatelessWidget {
  const DetailsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final draft = state.draft;
    if (draft == null) {
      return const Center(child: Text(AppStrings.selectTaskPrompt));
    }
    return _TaskEditor(notifier: notifier, state: state, draft: draft);
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
            TextButton(
              key: const ValueKey('add-subtask'),
              onPressed: canAddSubtask
                  ? () => showCreateTaskDialog(
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
