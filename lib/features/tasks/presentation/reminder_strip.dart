import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import 'reminders_notifier.dart';
import 'strings/reminder_strings.dart';
import 'tasks_scope.dart';
import 'theme/nexora_colors.dart';

/// Top of the centre pane on list views while at least one reminder is due. It
/// replaces the old full-width banner and keeps its behaviour: the first due
/// task, "+N more", and the fallback note when native notifications are off.
/// "Dismiss all" lives on the dashboard panel.
class ReminderStrip extends StatelessWidget {
  /// Below this width the strip stacks (see [build]).
  static const double _singleRowWidth = 760;

  const ReminderStrip({super.key, this.onShowDashboard});

  /// Opens the dashboard (the "+N more" link). Null hides the link target.
  final VoidCallback? onShowDashboard;

  @override
  Widget build(BuildContext context) {
    final notifier = ReminderScope.maybeOf(context);
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    final due = notifier.service.due;
    if (due.isEmpty) {
      return const SizedBox.shrink();
    }
    final c = NexoraColors.of(context);
    final first = due.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const ValueKey('reminder-banner'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.accentCyan),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stateText = Text(
                  first.missed
                      ? '${ReminderStrings.state(first.reminder)} · '
                            '${ReminderStrings.missedTag}'
                      : ReminderStrings.state(first.reminder),
                  style: NexoraText.label.copyWith(
                    color: first.missed ? c.statusOverdue : c.text2,
                  ),
                );
                final more = due.length > 1
                    ? TextButton(
                        key: const ValueKey('reminder-more'),
                        onPressed: onShowDashboard,
                        child: Text(ReminderStrings.more(due.length - 1)),
                      )
                    : null;
                final open = TextButton(
                  key: ValueKey('reminder-open-${first.taskId}'),
                  onPressed: () =>
                      TasksScope.of(context).revealTask(first.taskId),
                  child: const Text(ReminderStrings.openTask),
                );
                final done = FilledButton(
                  key: ValueKey('reminder-done-${first.taskId}'),
                  onPressed: () => notifier.service.acknowledge(first.taskId),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text(ReminderStrings.acknowledge),
                );
                final snooze = _SnoozeMenu(item: first, notifier: notifier);
                final bell = Icon(
                  Icons.notifications_none,
                  size: 18,
                  color: c.accentCyan,
                );
                // The task name is the point of the strip. The whole task name
                // is the tooltip when it is cut.
                Widget title(int lines) => Tooltip(
                  message: first.title,
                  waitDuration: const Duration(milliseconds: 500),
                  child: Text(
                    first.title,
                    maxLines: lines,
                    overflow: TextOverflow.ellipsis,
                    style: NexoraText.bodyStrong.copyWith(color: c.text1),
                  ),
                );

                // Wide: everything on one line, as before. Narrow: the name
                // keeps its own line (up to two) and the state and the actions
                // wrap below it, so the name never shrinks to nothing.
                if (constraints.maxWidth >= _singleRowWidth) {
                  return Row(
                    key: ValueKey('reminder-row-${first.taskId}'),
                    children: [
                      bell,
                      const SizedBox(width: 10),
                      Flexible(child: title(1)),
                      const SizedBox(width: 8),
                      stateText,
                      if (more != null) ...[const SizedBox(width: 8), more],
                      const Spacer(),
                      open,
                      snooze,
                      done,
                    ],
                  );
                }
                return Column(
                  key: ValueKey('reminder-row-${first.taskId}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: bell,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: title(2)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 28, right: 2),
                          child: stateText,
                        ),
                        ?more,
                        open,
                        snooze,
                        done,
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          if (!notifier.nativeAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                ReminderStrings.nativeUnavailable,
                style: NexoraText.caption.copyWith(color: c.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// The Snooze menu used by the strip and the dashboard: 10 minutes, 1 hour,
/// Tomorrow 09:00. It calls the same service functions as the details block.
class _SnoozeMenu extends StatelessWidget {
  const _SnoozeMenu({required this.item, required this.notifier});

  final DueReminder item;
  final RemindersNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return SnoozeMenuButton(
      key: ValueKey('reminder-snooze-menu-${item.taskId}'),
      taskId: item.taskId,
      service: notifier.service,
    );
  }
}

/// Snooze as a menu button. Item keys: `reminder-snooze10-<id>`,
/// `reminder-snooze60-<id>`, `reminder-snooze-tomorrow-<id>`.
class SnoozeMenuButton extends StatelessWidget {
  const SnoozeMenuButton({
    super.key,
    required this.taskId,
    required this.service,
    this.onSnoozed,
    this.buttonKey,
  });

  final String taskId;
  final ReminderService service;

  /// Overrides the key of the Snooze button.
  final Key? buttonKey;

  /// Called with the error text when snoozing failed (null on success).
  final void Function(String? error)? onSnoozed;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return MenuAnchor(
      builder: (context, controller, _) => TextButton(
        key: buttonKey ?? ValueKey('reminder-snooze-$taskId'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(ReminderStrings.snooze),
            Icon(Icons.expand_more, size: 16, color: c.accentCyan),
          ],
        ),
      ),
      menuChildren: [
        MenuItemButton(
          key: ValueKey('reminder-snooze10-$taskId'),
          onPressed: () {
            service.snooze(taskId, const Duration(minutes: 10));
            onSnoozed?.call(null);
          },
          child: const Text(ReminderStrings.snooze10),
        ),
        MenuItemButton(
          key: ValueKey('reminder-snooze60-$taskId'),
          onPressed: () {
            service.snooze(taskId, const Duration(hours: 1));
            onSnoozed?.call(null);
          },
          child: const Text(ReminderStrings.snooze1h),
        ),
        MenuItemButton(
          key: ValueKey('reminder-snooze-tomorrow-$taskId'),
          onPressed: () {
            final now = service.clock.toLocal(service.clock.nowUtc());
            final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
            final error = service.snoozeUntil(
              taskId,
              LocalWallTime.fromDateTime(tomorrow),
            );
            onSnoozed?.call(
              error == null ? null : ReminderStrings.errorMessage(error),
            );
          },
          child: const Text(ReminderStrings.snoozeTomorrow),
        ),
      ],
    );
  }
}
