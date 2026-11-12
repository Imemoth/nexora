import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'keyboard_actions.dart';
import 'tasks_scope.dart';

/// Keys that work in both panes. Ctrl is the command modifier.
const globalShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyF, control: true): TaskIntent(
    TaskCommand.focusSearch,
  ),
  SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true):
      TaskIntent(TaskCommand.newSubtask),
  SingleActivator(LogicalKeyboardKey.keyN, control: true): TaskIntent(
    TaskCommand.newTask,
  ),
  SingleActivator(LogicalKeyboardKey.keyS, control: true): TaskIntent(
    TaskCommand.saveDraft,
  ),
  SingleActivator(LogicalKeyboardKey.escape): TaskIntent(TaskCommand.escape),
};

/// Row navigation. Only the list pane binds these, so arrows in the details
/// editor (dropdowns, text fields) are never taken by the list.
const listShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowUp): TaskIntent(TaskCommand.moveUp),
  SingleActivator(LogicalKeyboardKey.arrowDown): TaskIntent(
    TaskCommand.moveDown,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): TaskIntent(
    TaskCommand.expand,
  ),
  SingleActivator(LogicalKeyboardKey.arrowLeft): TaskIntent(
    TaskCommand.collapse,
  ),
  SingleActivator(LogicalKeyboardKey.enter): TaskIntent(TaskCommand.focusTitle),
  SingleActivator(LogicalKeyboardKey.numpadEnter): TaskIntent(
    TaskCommand.focusTitle,
  ),
};

/// Wires [globalShortcuts] (and [listShortcuts] when [listNavigation] is set)
/// to [TaskCommands]. Wrap each pane in one. Keys reach the scope only when
/// focus is inside it, so the two panes never handle the same key twice.
class KeymapScope extends StatefulWidget {
  const KeymapScope({
    super.key,
    required this.child,
    this.listNavigation = false,
    this.inEditor = false,
  });

  final Widget child;

  /// Binds row navigation keys. Set on the list pane only.
  final bool listNavigation;

  /// Set on the details pane, so Esc returns focus to the list.
  final bool inEditor;

  @override
  State<KeymapScope> createState() => _KeymapScopeState();
}

class _KeymapScopeState extends State<KeymapScope> {
  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final commands = TaskCommands(
      notifier: notifier,
      focus: TaskKeyboardFocus.of(notifier),
      inEditor: widget.inEditor,
    );
    final shortcuts = <ShortcutActivator, Intent>{
      ...globalShortcuts,
      if (widget.listNavigation) ...listShortcuts,
    };
    return Actions(
      actions: <Type, Action<Intent>>{
        TaskIntent: TaskCommandAction(
          commands: commands,
          onInvoke: (command) => commands.run(command, context),
        ),
      },
      child: Shortcuts(shortcuts: shortcuts, child: widget.child),
    );
  }
}
