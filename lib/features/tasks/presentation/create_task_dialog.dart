import 'package:flutter/material.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/domain/parent_choices.dart';
import 'package:nexora/features/tasks/domain/task.dart';

import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'theme/nexora_colors.dart';

/// Opens the create dialog. With [parentId] it creates a subtask under that
/// task. Without it, it creates a root task in a project.
Future<bool?> showCreateTaskDialog(
  BuildContext context,
  TasksNotifier notifier, {
  String? parentId,
  String? parentTitle,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => CreateTaskDialog(
      notifier: notifier,
      parentId: parentId,
      parentTitle: parentTitle,
    ),
  );
}

/// Creates a root task or a subtask. A validation or save error keeps the
/// dialog open with the typed title. A creation that opens the unsaved-change
/// gate closes this dialog, and the gate takes over.
class CreateTaskDialog extends StatefulWidget {
  const CreateTaskDialog({
    super.key,
    required this.notifier,
    this.parentId,
    this.parentTitle,
  });

  final TasksNotifier notifier;
  final String? parentId;
  final String? parentTitle;

  @override
  State<CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<CreateTaskDialog> {
  final TextEditingController _title = TextEditingController();
  late String _projectId = _initialProjectId();
  late String? _parentId = widget.parentId;
  String? _error;
  bool _busy = false;

  bool get _isSubtask => widget.parentId != null;

  String _initialProjectId() {
    final selection = widget.notifier.state.selection;
    if (selection is ProjectSelection) {
      return selection.projectId;
    }
    final projects = widget.notifier.state.projects;
    return projects.isEmpty ? '' : projects.first.id;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<Task, WorkspaceError> result;
    final parentId = _parentId;
    if (parentId != null) {
      result = await widget.notifier.createSubtask(
        title: _title.text,
        parentId: parentId,
      );
    } else {
      result = await widget.notifier.createRootTask(
        title: _title.text,
        projectId: _projectId,
      );
    }
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        final messenger = ScaffoldMessenger.maybeOf(context);
        final gateOpened = widget.notifier.state.pending != null;
        // true tells the caller a task was created, so focus can move to it.
        Navigator.of(context).pop(true);
        if (!gateOpened) {
          messenger?.showSnackBar(
            const SnackBar(content: Text(AppStrings.taskCreated)),
          );
        }
      case Err(:final error):
        setState(() {
          _busy = false;
          _error = AppStrings.errorMessage(error);
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = widget.notifier.state.projects;
    final canCreate = _isSubtask || projects.isNotEmpty;
    final title = FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: TextField(
        key: const ValueKey('create-title'),
        controller: _title,
        // Creating is the point of the dialog: the title is ready to type into
        // (the default project or parent is already chosen), and Enter creates.
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: AppStrings.fieldTitle,
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
      ),
    );
    // Tab order is the visual order: Project (or the parent), Title, Cancel,
    // Create. Shift+Tab from the title reaches the project.
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: AlertDialog(
        title: Text(
          _isSubtask ? AppStrings.newSubtaskTitle : AppStrings.newTaskTitle,
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isSubtask) ...[
                FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: _ParentPicker(
                    notifier: widget.notifier,
                    initialParentId: widget.parentId!,
                    value: _parentId!,
                    onChanged: (id) => setState(() => _parentId = id),
                  ),
                ),
                const SizedBox(height: 12),
                title,
              ] else ...[
                if (projects.isNotEmpty) ...[
                  Text(
                    AppStrings.fieldProject,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: DropdownButton<String>(
                      key: const ValueKey('create-project'),
                      isExpanded: true,
                      value: _projectId,
                      items: [
                        for (final project in projects)
                          DropdownMenuItem<String>(
                            value: project.id,
                            child: Text(
                              project.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _projectId = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                title,
              ],
            ],
          ),
        ),
        actions: [
          FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: TextButton(
              key: const ValueKey('create-cancel'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.cancelAction),
            ),
          ),
          FocusTraversalOrder(
            order: const NumericFocusOrder(4),
            child: FilledButton(
              key: const ValueKey('create-submit'),
              onPressed: canCreate && !_busy ? _submit : null,
              child: const Text(AppStrings.createAction),
            ),
          ),
        ],
      ),
    );
  }
}

/// Parent of a new subtask: preselected to the task it was opened from, and
/// changeable to any other valid parent of the same project. Each choice shows
/// its ancestry so same-named tasks can be told apart; the project is shown as
/// fixed context.
class _ParentPicker extends StatelessWidget {
  const _ParentPicker({
    required this.notifier,
    required this.initialParentId,
    required this.value,
    required this.onChanged,
  });

  final TasksNotifier notifier;
  final String initialParentId;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final state = notifier.state;
    final origin = state.tasks[initialParentId];
    if (origin == null) {
      return const SizedBox.shrink();
    }
    final project = state.projects
        .where((p) => p.id == origin.projectId)
        .map((p) => p.name)
        .firstOrNull;
    final choices = subtaskParentChoices(
      tasks: state.tasks.values,
      projectId: origin.projectId,
    );
    // Keep the dropdown valid even if the origin is no longer a valid parent.
    final selected = choices.any((ch) => ch.task.id == value) ? value : null;
    final selectedChoice = choices
        .where((ch) => ch.task.id == selected)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (project != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${AppStrings.fieldProject}: $project',
              key: const ValueKey('create-parent-project'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexoraText.caption.copyWith(color: c.textMuted),
            ),
          ),
        // The parent is the one decision this dialog is about: it gets a calm
        // accent frame, an icon and a heavier label, in both themes.
        Container(
          key: const ValueKey('create-parent-card'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          decoration: BoxDecoration(
            color: c.accentCyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.accentCyan, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.subdirectory_arrow_right,
                    size: 16,
                    color: c.accentCyan,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppStrings.fieldParentTask.toUpperCase(),
                    style: NexoraText.overline.copyWith(color: c.accentCyan),
                  ),
                ],
              ),
              DropdownButton<String>(
                key: const ValueKey('create-parent'),
                isExpanded: true,
                value: selected,
                itemHeight: null,
                underline: const SizedBox.shrink(),
                selectedItemBuilder: (_) => [
                  for (final choice in choices)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppStrings.parentChoiceSummary([
                          ...choice.ancestors,
                          choice.task.title,
                        ]),
                        key: choice.task.id == selected
                            ? const ValueKey('create-parent-selected')
                            : null,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NexoraText.bodyStrong.copyWith(color: c.text1),
                      ),
                    ),
                ],
                items: [
                  for (final choice in choices)
                    DropdownMenuItem<String>(
                      key: ValueKey('create-parent-${choice.task.id}'),
                      value: choice.task.id,
                      child: Padding(
                        padding: EdgeInsets.only(left: choice.depth * 14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              choice.task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (choice.ancestors.isNotEmpty)
                              Text(
                                AppStrings.parentChoiceSummary(
                                  choice.ancestors,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: NexoraText.caption.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) {
                    onChanged(id);
                  }
                },
              ),
              if (selectedChoice != null)
                Text(
                  AppStrings.parentHelp,
                  style: NexoraText.caption.copyWith(color: c.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
