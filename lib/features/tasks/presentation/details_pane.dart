import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/edit_draft.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_completion.dart';
import 'package:nexora/features/tasks/domain/task_completion_tree.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'dashed_border.dart';
import 'delete_flow.dart';
import 'due_date_field.dart';
import 'keyboard_actions.dart';
import 'keycap.dart';
import 'keymap.dart';
import 'reminder_field.dart';
import 'status_badge.dart';
import 'strings/app_strings.dart';
import 'synced_text_field.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';
import 'theme/nexora_colors.dart';

/// Right pane: the editor for the selected task. Every edit goes to the
/// workspace draft. Save and Revert are enabled only for a dirty draft, and the
/// save bar stays pinned while the body scrolls.
class DetailsPane extends StatelessWidget {
  const DetailsPane({super.key, this.onClose});

  /// Shown as a Close button in the save bar (the overlay width only).
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final draft = state.draft;
    final c = NexoraColors.of(context);
    final Widget content;
    if (draft == null) {
      content = Column(
        children: [
          if (onClose != null)
            Align(
              alignment: Alignment.centerRight,
              child: _CloseButton(onClose: onClose!),
            ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      AppStrings.selectTaskPrompt,
                      style: NexoraText.bodyStrong.copyWith(color: c.text1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.selectTaskHint,
                      textAlign: TextAlign.center,
                      style: NexoraText.caption.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    } else {
      content = _TaskEditor(
        notifier: notifier,
        state: state,
        draft: draft,
        onClose: onClose,
      );
    }
    return KeymapScope(
      inEditor: true,
      child: ColoredBox(color: c.panel, child: content),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: AppStrings.closeDetails,
      icon: const Icon(Icons.close, size: 20),
      onPressed: onClose,
    );
  }
}

class _TaskEditor extends StatelessWidget {
  const _TaskEditor({
    required this.notifier,
    required this.state,
    required this.draft,
    required this.onClose,
  });

  final TasksNotifier notifier;
  final WorkspaceState state;
  final EditDraft draft;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final dirty = draft.isDirty;
    final error = state.error;
    final titleError = _isTitleError(error)
        ? AppStrings.errorMessage(error!)
        : null;
    final formError = error != null && !_isTitleError(error)
        ? AppStrings.errorMessage(error)
        : null;
    final projectName = state.tasks[draft.taskId] == null
        ? ''
        : state.projects
              .where((p) => p.id == state.tasks[draft.taskId]!.projectId)
              .map((p) => p.name)
              .firstOrNull;

    return Column(
      children: [
        _SaveBar(
          dirty: dirty,
          onSave: () => notifier.saveDraft(),
          onRevert: notifier.revertDraft,
          onClose: onClose,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (formError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    formError,
                    key: const ValueKey('editor-error'),
                    style: NexoraText.body.copyWith(color: c.statusOverdue),
                  ),
                ),
              _TaskGroup(
                notifier: notifier,
                state: state,
                draft: draft,
                titleError: titleError,
                projectName: projectName ?? '',
              ),
              const SizedBox(height: 14),
              ReminderField(
                key: ValueKey('reminder-${draft.taskId}'),
                taskId: draft.taskId,
              ),
              const SizedBox(height: 14),
              _Subtasks(notifier: notifier, state: state, draft: draft),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: DeleteTaskButton(taskId: draft.taskId),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _isTitleError(WorkspaceError? error) {
    return error == WorkspaceError.titleRequired ||
        error == WorkspaceError.titleTooLong;
  }
}

/// Pinned at the top, never scrolls: the state in words, Revert and Save.
class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.dirty,
    required this.onSave,
    required this.onRevert,
    required this.onClose,
  });

  final bool dirty;
  final VoidCallback onSave;
  final VoidCallback onRevert;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final tone = dirty ? c.statusReview : c.textMuted;
    return Container(
      key: const ValueKey('save-bar'),
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  dirty
                      ? AppStrings.unsavedIndicator
                      : AppStrings.savedIndicator,
                  key: dirty
                      ? const ValueKey('dirty-indicator')
                      : const ValueKey('saved-indicator'),
                  style: NexoraText.bodyStrong.copyWith(color: tone),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('revert'),
                onPressed: dirty ? onRevert : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text(AppStrings.revertAction),
              ),
              FilledButton(
                key: const ValueKey('save'),
                onPressed: dirty ? onSave : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(AppStrings.saveAction),
                    const SizedBox(width: 8),
                    const Keycap('Ctrl S', onFill: true),
                  ],
                ),
              ),
              if (onClose != null) _CloseButton(onClose: onClose!),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskGroup extends StatelessWidget {
  const _TaskGroup({
    required this.notifier,
    required this.state,
    required this.draft,
    required this.titleError,
    required this.projectName,
  });

  final TasksNotifier notifier;
  final WorkspaceState state;
  final EditDraft draft;
  final String? titleError;
  final String projectName;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.save_outlined, size: 14, color: c.textMuted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  AppStrings.taskGroupCaption.toUpperCase(),
                  style: NexoraText.overline.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SyncedTextField(
            key: ValueKey('title-${draft.taskId}'),
            value: draft.title,
            label: AppStrings.fieldTitle,
            errorText: titleError,
            focusNode: TaskKeyboardFocus.of(notifier).title,
            style: NexoraText.titleField.copyWith(color: c.text1),
            onChanged: (value) => notifier.editDraft(title: value),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _LabeledDropdown<TaskStatus>(
                  label: AppStrings.fieldStatus,
                  fieldKey: const ValueKey('status-dropdown'),
                  value: draft.status,
                  values: TaskStatus.values,
                  labelOf: AppStrings.statusLabel,
                  onChanged: (value) => notifier.editDraft(status: value),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LabeledDropdown<TaskPriority>(
                  label: AppStrings.fieldPriority,
                  fieldKey: const ValueKey('priority-dropdown'),
                  value: draft.priority,
                  values: TaskPriority.values,
                  labelOf: AppStrings.priorityLabel,
                  onChanged: (value) => notifier.editDraft(priority: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DueDateField(
                  key: const ValueKey('due-date-field'),
                  dueDate: draft.dueDate,
                  today: state.today,
                  onChanged: (date) => notifier.editDraft(
                    dueDate: date,
                    clearDueDate: date == null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.fieldProject,
                      style: NexoraText.label.copyWith(color: c.textMuted),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      key: const ValueKey('project-readonly'),
                      height: 40,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.panel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(
                        projectName,
                        overflow: TextOverflow.ellipsis,
                        style: NexoraText.body.copyWith(color: c.text2),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SyncedTextField(
            key: ValueKey('notes-${draft.taskId}'),
            value: draft.notes,
            label: AppStrings.fieldNotes,
            minLines: 4,
            maxLines: 8,
            onChanged: (value) => notifier.editDraft(notes: value),
          ),
        ],
      ),
    );
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
    final c = NexoraColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: NexoraText.label.copyWith(color: c.textMuted)),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          key: fieldKey,
          isExpanded: true,
          initialValue: value,
          dropdownColor: c.surface,
          borderRadius: BorderRadius.circular(12),
          style: NexoraText.body.copyWith(color: c.text1),
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

/// Heading with progress, one row per direct child, then Add subtask.
class _Subtasks extends StatelessWidget {
  const _Subtasks({
    required this.notifier,
    required this.state,
    required this.draft,
  });

  final TasksNotifier notifier;
  final WorkspaceState state;
  final EditDraft draft;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final completion = completionOf(draft.taskId, state.tasks);
    final children =
        state.tasks.values.where((t) => t.parentId == draft.taskId).toList()
          ..sort((a, b) {
            final byPosition = a.position.compareTo(b.position);
            return byPosition != 0 ? byPosition : a.id.compareTo(b.id);
          });
    final canAddSubtask = draft.status != TaskStatus.archived;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              AppStrings.subtasksHeader.toUpperCase(),
              style: NexoraText.overline.copyWith(color: c.textMuted),
            ),
            const Spacer(),
            _ChildSummary(completion: completion),
          ],
        ),
        if (children.isNotEmpty) const SizedBox(height: 8),
        for (final child in children)
          _SubtaskRow(task: child, onTap: () => notifier.selectTask(child.id)),
        const SizedBox(height: 8),
        DashedBorder(
          color: c.borderStrong,
          radius: 10,
          child: TextButton(
            key: const ValueKey('add-subtask'),
            onPressed: canAddSubtask
                ? () => openCreateTask(
                    context,
                    notifier,
                    parentId: draft.taskId,
                    parentTitle: draft.title,
                  )
                : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: c.text1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Icon(Icons.add, size: 16),
                Text(AppStrings.addSubtaskAction),
                Keycap('Ctrl Shift N'),
              ],
            ),
          ),
        ),
        if (!canAddSubtask)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              AppStrings.errorParentArchived,
              style: NexoraText.caption.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }
}

class _SubtaskRow extends StatelessWidget {
  const _SubtaskRow({required this.task, required this.onTap});

  final Task task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Semantics(
      button: true,
      label: '${task.title}, ${AppStrings.statusLabel(task.status)}',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('subtask-${task.id}'),
        borderRadius: BorderRadius.circular(8),
        hoverColor: c.surface,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              StatusRing(status: task.status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexoraText.bodyStrong.copyWith(
                    color: task.status == TaskStatus.done
                        ? c.textMuted
                        : c.text1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.statusLabel(task.status),
                style: NexoraText.label.copyWith(
                  color: statusColor(c, task.status),
                ),
              ),
            ],
          ),
        ),
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
    final c = NexoraColors.of(context);
    final fraction = completion.done / completion.total;
    return Row(
      key: const ValueKey('child-summary'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (completion.eligibleForReview) ...[
          Text(
            AppStrings.readyForReview,
            style: NexoraText.label.copyWith(color: c.statusReview),
          ),
          const SizedBox(width: 8),
        ],
        ExcludeSemantics(
          child: SizedBox(
            width: 44,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Container(color: c.border),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(color: c.statusDone),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          AppStrings.progress(completion.done, completion.total),
          style: NexoraText.label.copyWith(color: c.text2),
        ),
      ],
    );
  }
}
