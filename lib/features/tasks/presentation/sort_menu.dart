import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';

import 'package:nexora/app/theme.dart';

import 'focus_ring.dart';
import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// Chooses the display order of the task list. Sorting never changes stored
/// positions.
class SortMenu extends StatelessWidget {
  const SortMenu({super.key, required this.sort, required this.onSelected});

  final TaskSort sort;
  final ValueChanged<TaskSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    // The ring wraps the whole menu button: the button's own focus node sits
    // inside it.
    return FocusRing(
      radius: 10,
      child: PopupMenuButton<TaskSort>(
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
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.borderStrong),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  AppStrings.sortButton(sort),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexoraText.bodyStrong.copyWith(color: c.text1),
                ),
              ),
              Icon(Icons.expand_more, size: 18, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}
