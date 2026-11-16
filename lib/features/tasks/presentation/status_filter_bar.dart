import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'strings/app_strings.dart';
import 'tasks_scope.dart';
import 'theme/nexora_colors.dart';

/// The statuses offered as filters, after "All". Archived has no chip.
const _filterStatuses = [
  TaskStatus.open,
  TaskStatus.inProgress,
  TaskStatus.review,
  TaskStatus.done,
];

/// Filter chips: All, Open, In progress, Review, Done, each with its count.
/// Choosing a chip filters the list; it never gates and never touches the
/// draft (like sort).
class StatusFilterBar extends StatelessWidget {
  const StatusFilterBar({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          key: const ValueKey('filter-all'),
          label: AppStrings.statusFilterAll,
          count: state.statusCount(null),
          selected: state.statusFilter == null,
          onTap: () => notifier.filterStatus(null),
        ),
        for (final status in _filterStatuses)
          _Chip(
            key: ValueKey('filter-${status.name}'),
            label: AppStrings.statusLabel(status),
            count: state.statusCount(status),
            selected: state.statusFilter == status,
            onTap: () => notifier.filterStatus(status),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final text = selected ? c.onAccent : c.text1;
    return Semantics(
      button: true,
      selected: selected,
      label: AppStrings.statusFilterChip(label, count),
      excludeSemantics: true,
      child: Material(
        color: selected ? c.accentBlue : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? c.accentBlue : c.borderStrong),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          hoverColor: selected ? null : c.surface,
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: NexoraText.label.copyWith(fontSize: 13, color: text),
                ),
                const SizedBox(width: 6),
                Text(
                  count.toString(),
                  style: NexoraText.label.copyWith(
                    fontSize: 13,
                    color: selected ? c.onAccent : c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
