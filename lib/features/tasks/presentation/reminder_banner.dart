import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';

import 'reminders_notifier.dart';
import 'strings/reminder_strings.dart';
import 'tasks_scope.dart';

/// The in-app list of reminders that fired and wait for the user. It is shown
/// whether or not a native notification could be displayed, so it is also the
/// fallback when desktop notifications are unavailable.
class ReminderBanner extends StatelessWidget {
  const ReminderBanner({super.key});

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
    final shown = due.take(3).toList();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('reminder-banner'),
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alarm),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ReminderStrings.bannerTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (due.length > 1)
                  TextButton(
                    key: const ValueKey('reminder-dismiss-all'),
                    onPressed: () {
                      for (final item in due) {
                        notifier.service.acknowledge(item.taskId);
                      }
                    },
                    child: const Text(ReminderStrings.dismissAll),
                  ),
              ],
            ),
            if (!notifier.nativeAvailable)
              Text(
                ReminderStrings.nativeUnavailable,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            for (final item in shown) _Row(item: item, notifier: notifier),
            if (due.length > shown.length)
              Text(ReminderStrings.more(due.length - shown.length)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.notifier});

  final DueReminder item;
  final RemindersNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final service = notifier.service;
    return Row(
      key: ValueKey('reminder-row-${item.taskId}'),
      children: [
        Expanded(
          child: Text(
            item.missed
                ? '${item.title} (${ReminderStrings.missedTag})'
                : item.title,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          key: ValueKey('reminder-open-${item.taskId}'),
          onPressed: () => TasksScope.of(context).revealTask(item.taskId),
          child: const Text(ReminderStrings.openTask),
        ),
        TextButton(
          key: ValueKey('reminder-snooze10-${item.taskId}'),
          onPressed: () =>
              service.snooze(item.taskId, const Duration(minutes: 10)),
          child: const Text(ReminderStrings.snooze10),
        ),
        TextButton(
          key: ValueKey('reminder-done-${item.taskId}'),
          onPressed: () => service.acknowledge(item.taskId),
          child: const Text(ReminderStrings.acknowledge),
        ),
      ],
    );
  }
}
