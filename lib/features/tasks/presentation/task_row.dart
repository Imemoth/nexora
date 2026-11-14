import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/visible_task_row.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';

import 'status_badge.dart';
import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// One task in the list. Indentation shows depth. The chevron toggles children
/// without selecting the row. Status, due date and priority are text and
/// icons, never colour alone.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.row,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
    this.today,
  });

  final VisibleTaskRow row;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggle;

  /// Today's date, used to mark an overdue due date. Null skips the marking.
  final CalendarDate? today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = NexoraColors.of(context);
    final task = row.task;
    final completion = row.completion;
    final chipStyle = theme.textTheme.labelMedium;
    final now = today;
    final overdue =
        now != null && matchesSmartView(task, SmartView.overdue, now);

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: selected ? colors.selectedGradient : null,
          border: Border(
            bottom: BorderSide(color: colors.border),
            top: selected
                ? BorderSide(color: colors.accentBlue, width: 2)
                : BorderSide.none,
          ),
        ),
        child: InkWell(
          key: ValueKey('row-${task.id}'),
          // Keyboard focus stays on the list, so the rows themselves are not
          // focus targets. Enter would otherwise re-select instead of editing.
          canRequestFocus: false,
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
                            row.expanded
                                ? Icons.expand_less
                                : Icons.expand_more,
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
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusBadge(status: task.status),
                          if (task.dueDate case final due?)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  overdue
                                      ? Icons.warning_amber_outlined
                                      : Icons.event_outlined,
                                  size: 14,
                                  color: overdue
                                      ? colors.statusOverdue
                                      : colors.text2,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  AppStrings.dueLabel(due),
                                  style: overdue
                                      ? chipStyle?.copyWith(
                                          color: colors.statusOverdue,
                                          fontWeight: FontWeight.w700,
                                        )
                                      : chipStyle,
                                ),
                              ],
                            ),
                          if (task.priority != TaskPriority.none)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.flag_outlined,
                                  size: 14,
                                  color: _priorityColor(colors, task.priority),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  AppStrings.priorityLabel(task.priority),
                                  style: chipStyle,
                                ),
                              ],
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
                            Text(
                              AppStrings.readyForReview,
                              style: chipStyle?.copyWith(
                                color: colors.statusReview,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _priorityColor(NexoraColors colors, TaskPriority priority) {
    return switch (priority) {
      TaskPriority.high => colors.statusOverdue,
      TaskPriority.medium => colors.statusReview,
      TaskPriority.low => colors.statusOpen,
      TaskPriority.none => colors.text2,
    };
  }
}
