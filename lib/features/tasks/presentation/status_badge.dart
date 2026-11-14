import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// Icon and colour for a task status. Each status has its own icon shape and a
/// word, so it never relies on colour alone.
({IconData icon, Color color}) statusStyle(NexoraColors c, TaskStatus status) {
  return switch (status) {
    TaskStatus.open => (
      icon: Icons.radio_button_unchecked,
      color: c.statusOpen,
    ),
    TaskStatus.inProgress => (icon: Icons.timelapse, color: c.statusProgress),
    TaskStatus.review => (icon: Icons.change_history, color: c.statusReview),
    TaskStatus.done => (icon: Icons.check_circle_outline, color: c.statusDone),
    TaskStatus.archived => (
      icon: Icons.inventory_2_outlined,
      color: c.textMuted,
    ),
  };
}

/// A tinted pill with the status icon and its label.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final style = statusStyle(c, status);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.tint(style.color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 14, color: style.color),
            const SizedBox(width: 4),
            Text(
              AppStrings.statusLabel(status),
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: style.color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
