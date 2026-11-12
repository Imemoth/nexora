import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/visible_task_row.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';

import 'strings/app_strings.dart';

/// One task in the list. Indentation shows depth. The chevron toggles children
/// without selecting the row. Status, due date and priority are text, not
/// colour alone.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.row,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
  });

  final VisibleTaskRow row;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = row.task;
    final completion = row.completion;
    final chipStyle = theme.textTheme.labelMedium;

    return Material(
      color: selected
          ? theme.colorScheme.primary.withValues(alpha: 0.16)
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('row-${task.id}'),
        onTap: onSelect,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 + row.depth * 24.0, 8, 16, 8),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: row.hasChildren
                    ? IconButton(
                        key: ValueKey('chevron-${task.id}'),
                        tooltip: row.expanded
                            ? AppStrings.collapseTask
                            : AppStrings.expandTask,
                        icon: Icon(
                          row.expanded ? Icons.expand_less : Icons.expand_more,
                        ),
                        onPressed: onToggle,
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          AppStrings.statusLabel(task.status),
                          style: chipStyle,
                        ),
                        if (task.dueDate case final due?)
                          Text(AppStrings.dueLabel(due), style: chipStyle),
                        if (task.priority != TaskPriority.none)
                          Text(
                            AppStrings.priorityLabel(task.priority),
                            style: chipStyle,
                          ),
                        if (completion != null)
                          Text(
                            AppStrings.progress(
                              completion.done,
                              completion.total,
                            ),
                            key: ValueKey('progress-${task.id}'),
                            style: chipStyle,
                          ),
                        if (completion?.eligibleForReview ?? false)
                          Text(AppStrings.readyForReview, style: chipStyle),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
