import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/details_pane.dart';
import 'package:nexora/features/tasks/presentation/keyboard_actions.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/task_list_pane.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/unsaved_changes_host.dart';

import 'details_overlay.dart';
import 'sidebar_nav.dart';

/// Responsive desktop layout.
///
/// - 1100 px and wider: sidebar, list and details side by side.
/// - 900 to 1099 px: the details editor is an overlay over the list, shown while
///   a task is selected. Closing it goes through the unsaved-change gate.
/// - Below 900 px: the desktop-only notice is shown, the list stays usable and
///   no overlay opens.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.onExitApp});

  static const double sidebarWidth = 240;
  static const double detailsWidth = 360;
  static const double threePaneBreakpoint = 1100;
  static const double overlayBreakpoint = 900;

  /// Passed to the unsaved-change host. Tests inject a fake exit.
  final void Function()? onExitApp;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _closeOverlay(TasksNotifier notifier) {
    notifier.selectTask(null);
    // Return focus to the list's own keyboard node. The list keymap sits below
    // that node, so arrow keys and shortcuts reach it. A focus wrapper above
    // the list would not. Focus moves only when the close actually happened. A
    // dirty draft opens the gate instead, and the gate keeps focus.
    if (notifier.state.selectedTaskId == null) {
      final list = TaskKeyboardFocus.of(notifier).list;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          TaskKeyboardFocus.restore(list);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;

    return UnsavedChangesHost(
      onExitApp: widget.onExitApp,
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final threePane = width >= AppShell.threePaneBreakpoint;
            final compact = width < AppShell.overlayBreakpoint;
            final overlayOpen = !threePane && !compact && state.draft != null;

            final body = Row(
              children: [
                const SizedBox(
                  key: ValueKey('sidebar'),
                  width: AppShell.sidebarWidth,
                  child: SidebarNav(),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Column(
                    children: [
                      if (compact)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                          child: Text(
                            AppStrings.desktopOnlyNotice,
                            key: const ValueKey('desktop-only-notice'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      const Expanded(
                        child: TaskListPane(key: ValueKey('task-list-pane')),
                      ),
                    ],
                  ),
                ),
                if (threePane) ...[
                  const VerticalDivider(width: 1),
                  const SizedBox(
                    key: ValueKey('details-pane'),
                    width: AppShell.detailsWidth,
                    child: DetailsPane(),
                  ),
                ],
              ],
            );

            return Stack(
              children: [
                body,
                if (overlayOpen)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: AppShell.detailsWidth,
                    child: DetailsOverlay(
                      key: const ValueKey('details-overlay'),
                      onClose: () => _closeOverlay(notifier),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
