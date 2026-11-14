import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'status_badge.dart';
import 'strings/app_strings.dart';
import 'tasks_notifier.dart';
import 'theme/nexora_colors.dart';

/// One chip per status plus All, each with the number of tasks it would list in
/// the current view and search. Choosing a chip filters the list. It never
/// opens the unsaved-change gate and never changes the draft.
class StatusFilterBar extends StatelessWidget {
  const StatusFilterBar({
    super.key,
    required this.state,
    required this.notifier,
  });

  final WorkspaceState state;
  final TasksNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final colors = NexoraColors.of(context);
    final textTheme = Theme.of(context).textTheme;

    Widget chip({
      required Key key,
      required String label,
      required int count,
      required TaskStatus? status,
      IconData? icon,
      Color? iconColor,
    }) {
      final selected = state.statusFilter == status;
      return ChoiceChip(
        key: key,
        selected: selected,
        showCheckmark: false,
        avatar: selected
            ? Icon(Icons.check, size: 16, color: colors.text1)
            : (icon == null ? null : Icon(icon, size: 16, color: iconColor)),
        label: Text(AppStrings.filterChipLabel(label, count)),
        labelStyle: textTheme.labelLarge?.copyWith(
          color: selected ? colors.text1 : colors.text2,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
        backgroundColor: Colors.transparent,
        selectedColor: colors.accentBlue.withValues(alpha: 0.18),
        side: BorderSide(color: selected ? colors.accentBlue : colors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        visualDensity: VisualDensity.compact,
        onSelected: (_) => notifier.filterByStatus(status),
      );
    }

    return Semantics(
      label: AppStrings.filterLabel,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          chip(
            key: const ValueKey('filter-all'),
            label: AppStrings.filterAll,
            count: state.countForStatus(null),
            status: null,
          ),
          for (final status in TaskStatus.values)
            chip(
              key: ValueKey('filter-${status.name}'),
              label: AppStrings.statusLabel(status),
              count: state.countForStatus(status),
              status: status,
              icon: statusStyle(colors, status).icon,
              iconColor: statusStyle(colors, status).color,
            ),
        ],
      ),
    );
  }
}
