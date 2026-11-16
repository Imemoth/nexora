import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/visible_task_row.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'reminders_notifier.dart';
import 'status_badge.dart';
import 'strings/app_strings.dart';
import 'strings/reminder_strings.dart';
import 'theme/nexora_colors.dart';

/// One task in the list. Indentation and 1 px guide lines show depth. The
/// chevron toggles children without selecting the row. Status, due date,
/// priority, progress and reminder are words (or an icon with a tooltip), never
/// colour alone.
class TaskRow extends StatelessWidget {
  const TaskRow({
    super.key,
    required this.row,
    required this.selected,
    required this.today,
    required this.onSelect,
    required this.onToggle,
    this.listFocused = false,
    this.contextLabel,
  });

  final VisibleTaskRow row;
  final bool selected;
  final CalendarDate today;
  final VoidCallback onSelect;
  final VoidCallback onToggle;

  /// True while the list has keyboard focus. The selected row then draws the
  /// 2 px cyan ring. The rows themselves never take focus.
  final bool listFocused;

  /// Project and parent shown before the metadata when the row stands outside
  /// its own place in the tree (smart views, a search that hides the parent).
  final String? contextLabel;

  static const double indentStep = 28;
  static const double _padding = 10;
  static const double _chevronBox = 30;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final task = row.task;
    final closed =
        task.status == TaskStatus.done || task.status == TaskStatus.archived;
    final reminder = ReminderScope.maybeOf(context)?.service
        .reminderFor(task.id);
    final hasReminder =
        reminder != null && reminder.state != ReminderState.acknowledged;
    final completion = row.completion;
    final due = task.dueDate;
    final overdue = due != null && !closed && due.compareTo(today) < 0;
    final dueToday = due != null && due == today;
    final dueText = due == null
        ? null
        : AppStrings.friendlyDue(
            due,
            today,
            closed: closed,
            time: task.dueTime,
          );
    final hasPriority = task.priority != TaskPriority.none;
    final ready = completion?.eligibleForReview ?? false;

    final border = selected
        ? (listFocused
              ? Border.all(color: c.accentCyan, width: 2)
              : Border.all(color: c.borderStrong))
        : Border.all(color: Colors.transparent);

    final labelStyle = NexoraText.label.copyWith(color: c.text2);
    final semanticsLabel = [
      task.title,
      AppStrings.statusLabel(task.status),
      ?dueText,
      if (hasPriority) AppStrings.priorityLabel(task.priority),
      if (completion != null)
        AppStrings.progress(completion.done, completion.total),
      if (ready) AppStrings.readyForReview,
      ?contextLabel,
    ].join(', ');

    final card = Container(
      constraints: const BoxConstraints(minHeight: 42),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? c.surface2 : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: border.top,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('row-${task.id}'),
          // Keyboard focus stays on the list, so the rows themselves are not
          // focus targets. Enter would otherwise re-select instead of editing.
          canRequestFocus: false,
          hoverColor: c.surface,
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _padding,
              vertical: 4,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _chevronBox,
                  height: _chevronBox,
                  child: row.hasChildren
                      ? IconButton(
                          key: ValueKey('chevron-${task.id}'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: _chevronBox,
                            height: _chevronBox,
                          ),
                          tooltip: row.expanded
                              ? AppStrings.collapseTask
                              : AppStrings.expandTask,
                          icon: Icon(
                            row.expanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                          ),
                          onPressed: onToggle,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                StatusRing(status: task.status),
                const SizedBox(width: 10),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth,
                            ),
                            child: Text(
                              task.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NexoraText.bodyStrong.copyWith(
                                color: closed ? c.textMuted : c.text1,
                                decoration: closed
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: c.textMuted,
                              ),
                            ),
                          ),
                          if (contextLabel != null)
                            Tooltip(
                              message: contextLabel!,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 260,
                                ),
                                child: Text(
                                  contextLabel!,
                                  key: ValueKey('context-${task.id}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          if (hasReminder)
                            Tooltip(
                              message: ReminderStrings.state(reminder),
                              child: Icon(
                                Icons.notifications_none,
                                key: ValueKey('bell-${task.id}'),
                                size: 14,
                                color: c.accentCyan,
                              ),
                            ),
                          if (ready)
                            Text(
                              AppStrings.readyForReview,
                              style: labelStyle.copyWith(color: c.statusReview),
                            ),
                          if (completion != null)
                            _Progress(
                              key: ValueKey('progress-${task.id}'),
                              done: completion.done,
                              total: completion.total,
                              style: labelStyle,
                            ),
                          if (hasPriority)
                            Text(
                              AppStrings.priorityLabel(task.priority),
                              style: labelStyle,
                            ),
                          if (dueText != null)
                            Text(
                              dueText,
                              style: labelStyle.copyWith(
                                color: overdue
                                    ? c.statusOverdue
                                    : (dueToday ? c.accentCyan : c.text2),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                StatusBadge(status: task.status, onSelectedRow: selected),
              ],
            ),
          ),
        ),
      ),
    );

    final depth = row.depth;
    return Semantics(
      container: true,
      label: semanticsLabel,
      selected: selected,
      expanded: row.hasChildren ? row.expanded : null,
      child: Stack(
        children: [
          if (depth > 0)
            Positioned.fill(
              child: CustomPaint(
                painter: _GuidePainter(depth: depth, color: c.borderStrong),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: depth * indentStep),
            child: card,
          ),
        ],
      ),
    );
  }
}

/// "2/4" with a 44 x 4 px bar before it (`statusDone` on `border`).
class _Progress extends StatelessWidget {
  const _Progress({
    super.key,
    required this.done,
    required this.total,
    required this.style,
  });

  final int done;
  final int total;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final fraction = total == 0 ? 0.0 : done / total;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            width: 44,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Container(color: c.border),
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(color: c.statusDone),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(AppStrings.progress(done, total), style: style),
      ],
    );
  }
}

/// One 1 px vertical line per ancestor level, full row height, so the lines
/// join between rows.
class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.depth, required this.color});

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 1; level <= depth; level++) {
      final x =
          TaskRow._padding +
          (level - 1) * TaskRow.indentStep +
          TaskRow._chevronBox / 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) =>
      old.depth != depth || old.color != color;
}
