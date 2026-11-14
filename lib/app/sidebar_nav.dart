import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/delete_flow.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'project_tile.dart';
import 'smart_view_tile.dart';

/// Left pane: brand, smart views, then projects, and a saved-status card at
/// the bottom. Counts come from the workspace.
class SidebarNav extends StatelessWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final selection = state.selection;
    final textTheme = Theme.of(context).textTheme;
    final colors = NexoraColors.of(context);

    return Material(
      color: colors.panel,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 16, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: colors.brandGradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: colors.glow, blurRadius: 18),
                          ],
                        ),
                        child: Icon(
                          Icons.hub_outlined,
                          color: colors.onAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppStrings.appName,
                            style: textTheme.titleLarge,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final view in SmartView.values)
                  SmartViewTile(
                    key: ValueKey('nav-${view.name}'),
                    view: view,
                    count: state.countFor(SmartViewSelection(view)),
                    selected:
                        selection is SmartViewSelection &&
                        selection.view == view,
                    onTap: () => notifier.selectView(view),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 4),
                  child: Text(
                    AppStrings.projectsHeader,
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ),
                for (final project in state.projects)
                  ProjectTile(
                    key: ValueKey('nav-project-${project.id}'),
                    project: project,
                    count: state.countFor(ProjectSelection(project.id)),
                    selected:
                        selection is ProjectSelection &&
                        selection.projectId == project.id,
                    progress: _progressOf(state.tasks.values, project.id),
                    canDelete: state.projects.length > 1,
                    onTap: () => notifier.selectProject(project.id),
                    onDelete: () => deleteProjectWithConfirmation(
                      context,
                      notifier,
                      project.id,
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              key: const ValueKey('saved-status'),
              decoration: BoxDecoration(
                gradient: colors.cardGradient,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: colors.statusDone,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppStrings.savedOnDevice,
                        style: textTheme.labelLarge?.copyWith(
                          color: colors.text1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double? _progressOf(Iterable<Task> tasks, String projectId) {
    var done = 0;
    var total = 0;
    for (final task in tasks) {
      if (task.projectId != projectId || task.status == TaskStatus.archived) {
        continue;
      }
      total++;
      if (task.status == TaskStatus.done) {
        done++;
      }
    }
    return total == 0 ? null : done / total;
  }
}
