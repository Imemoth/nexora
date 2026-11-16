import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// The colour of a status. Always shown beside its word, never alone. An
/// archived task is muted.
Color statusColor(NexoraColors c, TaskStatus status) => switch (status) {
  TaskStatus.open => c.statusOpen,
  TaskStatus.inProgress => c.statusProgress,
  TaskStatus.review => c.statusReview,
  TaskStatus.done => c.statusDone,
  TaskStatus.archived => c.textMuted,
};

/// The status word in a fixed-width badge: 92 px, radius 6, `surface2` ground
/// (`surface` on a selected row, which is already `surface2`).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.onSelectedRow = false,
  });

  final TaskStatus status;
  final bool onSelectedRow;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Container(
      width: 92,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onSelectedRow ? c.surface : c.surface2,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        AppStrings.statusLabel(status),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: NexoraText.label.copyWith(
          color: statusColor(c, status),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// The 16 px status ring: a 2 px stroke in the status colour, filled when the
/// task is done.
class StatusRing extends StatelessWidget {
  const StatusRing({super.key, required this.status, this.size = 16});

  final TaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(NexoraColors.of(context), status);
    final done = status == TaskStatus.done;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
      child: done
          ? Icon(
              Icons.check,
              size: size - 6,
              color: NexoraColors.of(context).background,
            )
          : null,
    );
  }
}
