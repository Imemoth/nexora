import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nexora/features/tasks/application/visible_task_row.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'create_task_dialog.dart';
import 'tasks_notifier.dart';

/// Every keyboard command the task workspace understands.
enum TaskCommand {
  moveUp,
  moveDown,
  expand,
  collapse,
  focusTitle,
  escape,
  focusSearch,
  newTask,
  newSubtask,
  saveDraft,
}

/// One intent type for all commands. [Actions] dispatches on [command].
final class TaskIntent extends Intent {
  const TaskIntent(this.command);

  final TaskCommand command;
}

/// Focus nodes shared by the list pane and the details pane.
///
/// The nodes are owned here, one set per [TasksNotifier], so the two panes can
/// reach each other without a global. Nothing is disposed: the nodes live as
/// long as the notifier that keys them.
final class TaskKeyboardFocus {
  TaskKeyboardFocus._();

  static final Expando<TaskKeyboardFocus> _byNotifier = Expando(
    'task-keyboard-focus',
  );

  /// The registry for [notifier], created on first use.
  static TaskKeyboardFocus of(TasksNotifier notifier) {
    return _byNotifier[notifier] ??= TaskKeyboardFocus._();
  }

  /// Keyboard focus for the task list. Arrow keys and Enter act here.
  final FocusNode list = FocusNode(debugLabel: 'task-list');

  /// The search field.
  final FocusNode search = FocusNode(debugLabel: 'task-search');

  /// The details title field.
  final FocusNode title = FocusNode(debugLabel: 'details-title');

  /// Returns focus to [node] if it is still in the tree.
  static void restore(FocusNode? node) {
    if (node == null || node.context == null || !node.canRequestFocus) {
      return;
    }
    node.requestFocus();
  }
}

/// Runs [TaskCommand]s against the notifier. Stateless apart from its inputs.
final class TaskCommands {
  TaskCommands({
    required this.notifier,
    required this.focus,
    required this.inEditor,
  });

  final TasksNotifier notifier;
  final TaskKeyboardFocus focus;

  /// True when the command comes from the details pane.
  final bool inEditor;

  /// Whether [command] should be handled now. A disabled command is not
  /// consumed, so the key reaches the focused text field or widget.
  bool isEnabled(TaskCommand command) {
    final typingInSearch = focus.search.hasPrimaryFocus;
    return switch (command) {
      TaskCommand.moveUp ||
      TaskCommand.moveDown ||
      TaskCommand.escape ||
      TaskCommand.focusSearch ||
      TaskCommand.newTask ||
      TaskCommand.saveDraft => true,
      TaskCommand.expand ||
      TaskCommand.collapse ||
      TaskCommand.focusTitle => !typingInSearch,
      TaskCommand.newSubtask => _subtaskTarget() != null,
    };
  }

  void run(TaskCommand command, BuildContext context) {
    switch (command) {
      case TaskCommand.moveUp:
        _moveBy(-1);
      case TaskCommand.moveDown:
        _moveBy(1);
      case TaskCommand.expand:
        _expand();
      case TaskCommand.collapse:
        _collapse();
      case TaskCommand.focusTitle:
        focus.title.requestFocus();
      case TaskCommand.escape:
        _escape();
      case TaskCommand.focusSearch:
        focus.search.requestFocus();
      case TaskCommand.newTask:
        unawaited(_openCreate(context));
      case TaskCommand.newSubtask:
        final target = _subtaskTarget();
        if (target != null) {
          unawaited(
            _openCreate(
              context,
              parentId: target.id,
              parentTitle: target.title,
            ),
          );
        }
      case TaskCommand.saveDraft:
        if (notifier.state.draft?.isDirty ?? false) {
          unawaited(notifier.saveDraft());
        }
    }
  }

  VisibleTaskRow? _selectedRow() {
    final id = notifier.state.selectedTaskId;
    if (id == null) {
      return null;
    }
    for (final row in notifier.state.visibleRows) {
      if (row.task.id == id) {
        return row;
      }
    }
    return null;
  }

  /// Up and Down go through the gate like a click. With no selection, Down
  /// picks the first row and Up picks the last.
  void _moveBy(int delta) {
    final rows = notifier.state.visibleRows;
    if (rows.isEmpty) {
      return;
    }
    final index = rows.indexWhere(
      (row) => row.task.id == notifier.state.selectedTaskId,
    );
    final int target;
    if (index == -1) {
      target = delta > 0 ? 0 : rows.length - 1;
    } else {
      target = index + delta;
      if (target < 0 || target >= rows.length) {
        return;
      }
    }
    notifier.selectTask(rows[target].task.id);
  }

  /// Expands a collapsed parent. On an expanded parent, moves to its first
  /// child, which goes through the gate. A leaf does nothing.
  void _expand() {
    final row = _selectedRow();
    if (row == null || !row.hasChildren) {
      return;
    }
    if (!row.expanded) {
      notifier.toggleExpanded(row.task.id);
      return;
    }
    final rows = notifier.state.visibleRows;
    final index = rows.indexWhere((r) => r.task.id == row.task.id);
    if (index == -1 || index + 1 >= rows.length) {
      return;
    }
    final next = rows[index + 1];
    if (next.task.parentId == row.task.id) {
      notifier.selectTask(next.task.id);
    }
  }

  /// Collapses an expanded row. Otherwise moves to the parent row, when the
  /// parent is visible in the current list.
  void _collapse() {
    final row = _selectedRow();
    if (row == null) {
      return;
    }
    if (row.hasChildren && row.expanded) {
      notifier.toggleExpanded(row.task.id);
      return;
    }
    final parentId = row.task.parentId;
    if (parentId == null) {
      return;
    }
    final parentVisible = notifier.state.visibleRows.any(
      (r) => r.task.id == parentId,
    );
    if (parentVisible) {
      notifier.selectTask(parentId);
    }
  }

  /// From the details pane, or with the search field focused, returns focus
  /// to the list. In the list it clears the selection, through the gate.
  void _escape() {
    if (inEditor || focus.search.hasPrimaryFocus) {
      focus.list.requestFocus();
      return;
    }
    notifier.selectTask(null);
  }

  /// The selected task as a subtask parent, or null when there is none or it
  /// is archived. Uses the draft's status and title when the draft is for it.
  ({String id, String title})? _subtaskTarget() {
    final state = notifier.state;
    final id = state.selectedTaskId;
    final task = id == null ? null : state.tasks[id];
    if (task == null) {
      return null;
    }
    final draft = state.draft;
    if (draft != null && draft.taskId == task.id) {
      if (draft.status == TaskStatus.archived) {
        return null;
      }
      return (id: task.id, title: draft.title);
    }
    if (task.status == TaskStatus.archived) {
      return null;
    }
    return (id: task.id, title: task.title);
  }

  /// Opens the create dialog. Focus rules are in [openCreateTask].
  Future<void> _openCreate(
    BuildContext context, {
    String? parentId,
    String? parentTitle,
  }) => openCreateTask(
    context,
    notifier,
    parentId: parentId,
    parentTitle: parentTitle,
  );
}

/// Adapts [TaskCommands] to the [Actions] system.
final class TaskCommandAction extends Action<TaskIntent> {
  TaskCommandAction({required this.commands, required this.onInvoke});

  final TaskCommands commands;

  /// Runs the command with the widget's context for dialogs.
  final void Function(TaskCommand command) onInvoke;

  @override
  bool isEnabled(TaskIntent intent) => commands.isEnabled(intent.command);

  @override
  Object? invoke(TaskIntent intent) {
    onInvoke(intent.command);
    return null;
  }
}

/// Opens the create dialog from any entry point, so every route gets the same
/// focus rules. After a create, focus moves to the details title (spec 5.5). If
/// the create opened the unsaved-change gate, the gate keeps focus. A dialog
/// that closes without a create gives focus back to where it was.
Future<void> openCreateTask(
  BuildContext context,
  TasksNotifier notifier, {
  String? parentId,
  String? parentTitle,
}) async {
  final previous = FocusManager.instance.primaryFocus;
  final created = await showCreateTaskDialog(
    context,
    notifier,
    parentId: parentId,
    parentTitle: parentTitle,
  );
  if (!context.mounted) {
    return;
  }
  if (created == true && notifier.state.pending == null) {
    final title = TaskKeyboardFocus.of(notifier).title;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => TaskKeyboardFocus.restore(title),
    );
    return;
  }
  TaskKeyboardFocus.restore(previous);
}
