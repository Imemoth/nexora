import 'package:flutter/material.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/domain/task.dart';

import 'strings/app_strings.dart';
import 'tasks_notifier.dart';

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
    final parentId = widget.parentId;
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
    return AlertDialog(
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
              Text(
                AppStrings.fieldParent,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(widget.parentTitle ?? ''),
              const SizedBox(height: 12),
            ],
            TextField(
              key: const ValueKey('create-title'),
              controller: _title,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: AppStrings.fieldTitle,
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            if (!_isSubtask && projects.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                AppStrings.fieldProject,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              DropdownButton<String>(
                key: const ValueKey('create-project'),
                isExpanded: true,
                value: _projectId,
                items: [
                  for (final project in projects)
                    DropdownMenuItem<String>(
                      value: project.id,
                      child: Text(project.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _projectId = value);
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('create-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancelAction),
        ),
        FilledButton(
          key: const ValueKey('create-submit'),
          onPressed: canCreate && !_busy ? _submit : null,
          child: const Text(AppStrings.createAction),
        ),
      ],
    );
  }
}
