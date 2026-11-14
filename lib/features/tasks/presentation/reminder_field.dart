import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import 'reminders_notifier.dart';
import 'strings/reminder_strings.dart';

/// The reminder editor inside the task details panel. Changes apply at once and
/// are not part of the task's Save/Revert draft: a reminder is device-local, so
/// it is never part of a task edit and never synchronized.
class ReminderField extends StatefulWidget {
  const ReminderField({super.key, required this.taskId});

  final String taskId;

  @override
  State<ReminderField> createState() => _ReminderFieldState();
}

class _ReminderFieldState extends State<ReminderField> {
  String? _error;

  Future<void> _pick(RemindersNotifier notifier, Reminder? current) async {
    final service = notifier.service;
    final now = service.clock.toLocal(service.clock.nowUtc());
    final initial = current?.remindAt ?? now;
    final date = await showDatePicker(
      context: context,
      helpText: ReminderStrings.pickDate,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      helpText: ReminderStrings.pickTime,
      initialTime: TimeOfDay(
        hour: current?.remindAt.hour ?? 9,
        minute: current?.remindAt.minute ?? 0,
      ),
    );
    if (time == null || !mounted) {
      return;
    }
    final error = service.setReminder(
      widget.taskId,
      LocalWallTime(date.year, date.month, date.day, time.hour, time.minute),
    );
    setState(() {
      _error = error == null ? null : ReminderStrings.errorMessage(error);
    });
  }

  void _snoozeTomorrow(RemindersNotifier notifier) {
    final service = notifier.service;
    final now = service.clock.toLocal(service.clock.nowUtc());
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final error = service.snoozeUntil(
      widget.taskId,
      LocalWallTime.fromDateTime(tomorrow),
    );
    setState(() {
      _error = error == null ? null : ReminderStrings.errorMessage(error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ReminderScope.maybeOf(context);
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    final service = notifier.service;
    final reminder = service.reminderFor(widget.taskId);
    final active =
        reminder != null && reminder.state != ReminderState.acknowledged;
    final label = reminder == null
        ? ReminderStrings.noReminder
        : '${ReminderStrings.when(reminder.snoozeUntilUtc == null ? reminder.remindAt : service.clock.toLocal(reminder.snoozeUntilUtc!))}'
              ' - ${ReminderStrings.state(reminder)}';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        key: const ValueKey('reminder-field'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ReminderStrings.fieldReminder, style: textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('reminder-button'),
                  onPressed: () => _pick(notifier, reminder),
                  icon: const Icon(Icons.alarm),
                  label: Text(label, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (reminder != null)
                IconButton(
                  key: const ValueKey('reminder-clear'),
                  tooltip: ReminderStrings.clearReminder,
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    service.cancel(widget.taskId);
                    setState(() => _error = null);
                  },
                ),
            ],
          ),
          if (reminder?.state == ReminderState.notified)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: const ValueKey('reminder-ack'),
                  onPressed: () => service.acknowledge(widget.taskId),
                  child: const Text(ReminderStrings.acknowledge),
                ),
                PopupMenuButton<String>(
                  key: const ValueKey('reminder-snooze'),
                  tooltip: ReminderStrings.snooze,
                  onSelected: (value) {
                    switch (value) {
                      case '10':
                        service.snooze(
                          widget.taskId,
                          const Duration(minutes: 10),
                        );
                      case '60':
                        service.snooze(widget.taskId, const Duration(hours: 1));
                      default:
                        _snoozeTomorrow(notifier);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: '10',
                      child: Text(ReminderStrings.snooze10),
                    ),
                    PopupMenuItem(
                      value: '60',
                      child: Text(ReminderStrings.snooze1h),
                    ),
                    PopupMenuItem(
                      value: 'tomorrow',
                      child: Text(ReminderStrings.snoozeTomorrow),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(ReminderStrings.snooze),
                  ),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_error!, key: const ValueKey('reminder-error')),
            ),
          if (active || reminder == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                ReminderStrings.deviceOnly,
                key: const ValueKey('reminder-device-only'),
                style: textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
