import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/presentation/delete_flow.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_scope.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'account_actions.dart';
import 'account_panel.dart';
import 'conflict_panel.dart';
import 'nav_tile.dart';
import 'project_tile.dart';
import 'smart_view_tile.dart';
import 'sync_card.dart';
import 'sync_panel.dart';

/// Left pane: brand, views, projects, and the sync card pinned at the bottom.
/// Counts come from the workspace.
class SidebarNav extends StatelessWidget {
  const SidebarNav({
    super.key,
    this.syncPanel,
    this.accountPanel,
    this.importPanel,
    this.conflictPanel,
  });

  final SyncPanel? syncPanel;
  final AccountPanel? accountPanel;
  final ImportPanel? importPanel;
  final ConflictPanel? conflictPanel;

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final selection = state.selection;
    final c = NexoraColors.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
              children: [
                const _BrandRow(),
                const SizedBox(height: 18),
                _SectionHeading(label: AppStrings.viewsHeader),
                NavTile(
                  key: const ValueKey('nav-dashboard'),
                  icon: Icons.home_outlined,
                  label: AppStrings.dashboardTitle,
                  count: -1,
                  selected: selection is DashboardSelection,
                  onTap: notifier.selectDashboard,
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
                const SizedBox(height: 16),
                _SectionHeading(
                  label: AppStrings.projectsHeader,
                  action: IconButton(
                    key: const ValueKey('nav-new-project'),
                    tooltip: AppStrings.newProjectAction,
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: () => showNewProjectDialog(context),
                  ),
                ),
                for (var i = 0; i < state.projects.length; i++)
                  ProjectTile(
                    key: ValueKey('nav-project-${state.projects[i].id}'),
                    project: state.projects[i],
                    index: i,
                    count: state.countFor(
                      ProjectSelection(state.projects[i].id),
                    ),
                    selected:
                        selection is ProjectSelection &&
                        selection.projectId == state.projects[i].id,
                    onTap: () => notifier.selectProject(state.projects[i].id),
                    trailing:
                        selection is ProjectSelection &&
                            selection.projectId == state.projects[i].id
                        ? _ProjectMenu(
                            projectId: state.projects[i].id,
                            canDelete: state.projects.length > 1,
                          )
                        : null,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SyncCard(
              syncPanel: syncPanel,
              accountPanel: accountPanel,
              importPanel: importPanel,
              conflictPanel: conflictPanel,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.accentBlue,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            AppStrings.brandMark,
            style: TextStyle(
              fontFamily: nexoraDisplayFont,
              fontFamilyFallback: nexoraFontFallback,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: c.onAccent,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          AppStrings.appName,
          style: NexoraText.titleDialog.copyWith(color: c.text1),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              label.toUpperCase(),
              style: NexoraText.overline.copyWith(color: c.textMuted),
            ),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

/// The selected project's "more" menu. Delete is disabled for the last project.
class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({required this.projectId, required this.canDelete});

  final String projectId;
  final bool canDelete;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return PopupMenuButton<String>(
      key: const ValueKey('project-menu'),
      tooltip: AppStrings.moreActions,
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: Icon(Icons.more_horiz, size: 18, color: c.text2),
      onSelected: (_) => deleteProjectWithConfirmation(
        context,
        TasksScope.of(context),
        projectId,
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          key: const ValueKey('delete-project'),
          value: 'delete',
          enabled: canDelete,
          child: Text(
            AppStrings.deleteProjectAction,
            style: TextStyle(color: canDelete ? c.statusOverdue : null),
          ),
        ),
      ],
    );
  }
}
