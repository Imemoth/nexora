import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';

import 'strings/app_strings.dart';

/// Chooses the display order of the task list. Sorting never changes stored
/// positions.
class SortMenu extends StatelessWidget {
  const SortMenu({super.key, required this.sort, required this.onSelected});

  final TaskSort sort;
  final ValueChanged<TaskSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TaskSort>(
      key: const ValueKey('sort-menu'),
      tooltip: AppStrings.sortTooltip,
      initialValue: sort,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in TaskSort.values)
          PopupMenuItem<TaskSort>(
            value: option,
            child: Text(AppStrings.sortLabel(option)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppStrings.sortLabel(sort)),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
