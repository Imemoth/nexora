import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';

import 'project_tile.dart';
import 'smart_view_tile.dart';

/// Left pane: smart views, then projects. Counts come from the workspace.
class SidebarNav extends StatelessWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final selection = state.selection;
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(AppStrings.appName, style: textTheme.titleLarge),
        ),
        for (final view in SmartView.values)
          SmartViewTile(
            key: ValueKey('nav-${view.name}'),
            view: view,
            count: state.countFor(SmartViewSelection(view)),
            selected: selection is SmartViewSelection && selection.view == view,
            onTap: () => notifier.selectView(view),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(AppStrings.projectsHeader, style: textTheme.labelLarge),
        ),
        for (final project in state.projects)
          ProjectTile(
            key: ValueKey('nav-project-${project.id}'),
            project: project,
            count: state.countFor(ProjectSelection(project.id)),
            selected:
                selection is ProjectSelection &&
                selection.projectId == project.id,
            onTap: () => notifier.selectProject(project.id),
          ),
      ],
    );
  }
}
