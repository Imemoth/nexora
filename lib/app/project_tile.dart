import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

import 'nav_tile.dart';

/// The colour of the dot for the project at [index]. Derived from the position
/// in the list, never stored (muted, blue, violet, done, review, cyan, repeat).
Color projectDotColor(NexoraColors c, int index) {
  final palette = [
    c.textMuted,
    c.accentBlue,
    c.accentViolet,
    c.statusDone,
    c.statusReview,
    c.accentCyan,
  ];
  return palette[index % palette.length];
}

/// Sidebar entry for a project.
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.index,
    required this.count,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final Project project;
  final int index;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return NavTile(
      dotColor: projectDotColor(NexoraColors.of(context), index),
      label: project.name,
      count: count,
      selected: selected,
      onTap: onTap,
      trailing: trailing,
    );
  }
}
