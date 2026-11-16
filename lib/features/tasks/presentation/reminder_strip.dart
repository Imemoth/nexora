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
            child: Row(
              key: ValueKey('reminder-row-${first.taskId}'),
              children: [
                Icon(Icons.notifications_none, size: 18, color: c.accentCyan),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    first.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NexoraText.bodyStrong.copyWith(color: c.text1),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  first.missed
                      ? '${ReminderStrings.state(first.reminder)} · '
                            '${ReminderStrings.missedTag}'
                      : ReminderStrings.state(first.reminder),
                  style: NexoraText.label.copyWith(
                    color: first.missed ? c.statusOverdue : c.text2,
                  ),
                ),
                if (due.length > 1) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    key: const ValueKey('reminder-more'),
                    onPressed: onShowDashboard,
                    child: Text(ReminderStrings.more(due.length - 1)),
                  ),
                ],
                const Spacer(),
                TextButton(
                  key: ValueKey('reminder-open-${first.taskId}'),
                  onPressed: () =>
                      TasksScope.of(context).revealTask(first.taskId),
                  child: const Text(ReminderStrings.openTask),
                ),
                _SnoozeMenu(item: first, notifier: notifier),
                FilledButton(
                  key: ValueKey('reminder-done-${first.taskId}'),
                  onPressed: () => notifier.service.acknowledge(first.taskId),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text(ReminderStrings.acknowledge),
                ),
              ],
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
