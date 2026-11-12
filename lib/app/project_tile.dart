import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import 'nav_tile.dart';

/// Sidebar entry for a project.
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final Project project;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NavTile(
      icon: Icons.folder_outlined,
      label: project.name,
      count: count,
      selected: selected,
      onTap: onTap,
    );
  }
}
