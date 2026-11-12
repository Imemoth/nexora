import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/details_pane.dart';
import 'package:nexora/features/tasks/presentation/task_list_pane.dart';

import 'sidebar_nav.dart';

/// Three-pane desktop layout. At 1100 px and wider the details pane sits
/// beside the list. Below that it is hidden in Task 3 and becomes an overlay
/// in Task 7.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  static const double sidebarWidth = 240;
  static const double detailsWidth = 360;
  static const double threePaneBreakpoint = 1100;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final threePane = constraints.maxWidth >= threePaneBreakpoint;
          return Row(
            children: [
              const SizedBox(
                key: ValueKey('sidebar'),
                width: sidebarWidth,
                child: SidebarNav(),
              ),
              const VerticalDivider(width: 1),
              const Expanded(
                child: TaskListPane(key: ValueKey('task-list-pane')),
              ),
              if (threePane) ...[
                const VerticalDivider(width: 1),
                const SizedBox(
                  key: ValueKey('details-pane'),
                  width: detailsWidth,
                  child: DetailsPane(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
