import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'nav_tile.dart';

/// Sidebar entry for a project, with a completion bar and a menu that deletes
/// the project. The menu item is disabled for the last remaining project.
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.onDelete,
    required this.canDelete,
    this.progress,
  });

  final Project project;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// False for the only remaining project.
  final bool canDelete;

  /// Done tasks divided by all tasks, or null when the project has none.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    return NavTile(
      icon: Icons.folder_outlined,
      label: project.name,
      count: count,
      selected: selected,
      onTap: onTap,
      progress: progress,
      action: PopupMenuButton<void>(
        key: ValueKey('project-menu-${project.id}'),
        tooltip: AppStrings.projectActionsTooltip,
        icon: Icon(Icons.more_vert, size: 20, color: colors.text2),
        itemBuilder: (context) => [
          PopupMenuItem<void>(
            key: ValueKey('project-delete-${project.id}'),
            enabled: canDelete,
            onTap: onDelete,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: canDelete ? colors.statusOverdue : colors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  AppStrings.deleteProjectAction,
                  style: TextStyle(
                    color: canDelete ? colors.statusOverdue : colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
