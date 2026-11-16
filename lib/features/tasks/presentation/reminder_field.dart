import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import 'dashed_border.dart';
import 'reminder_dialog.dart';
import 'reminder_strip.dart';
import 'reminders_notifier.dart';
import 'strings/reminder_strings.dart';
import 'theme/nexora_colors.dart';

/// The reminder block in the details pane, outside the task group. Changes
/// apply at once and are never part of the task's Save/Revert draft: a reminder
/// is device-local, so it is never part of a task edit and never synchronized.
class ReminderField extends StatefulWidget {
  const ReminderField({super.key, required this.taskId});

  final String taskId;

  @override
  State<ReminderField> createState() => _ReminderFieldState();
}

class _ReminderFieldState extends State<ReminderField> {
  String? _error;

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(RemindersNotifier notifier, Reminder? current) async {
    setState(() => _error = null);
    final saved = await showReminderDialog(
      context,
      notifier: notifier,
      taskId: widget.taskId,
      current: current,
    );
    if (saved == true && mounted) {
      _toast(ReminderStrings.saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ReminderScope.maybeOf(context);
    if (notifier == null) {
      return const SizedBox.shrink();
    }
    final c = NexoraColors.of(context);
    final service = notifier.service;
    final reminder = service.reminderFor(widget.taskId);
    final label = reminder == null
        ? ReminderStrings.noReminder
        : '${ReminderStrings.friendlyWhen(reminder.snoozeUntilUtc == null ? reminder.remindAt : service.clock.toLocal(reminder.snoozeUntilUtc!))}'
              ' · ${ReminderStrings.state(reminder)}';
    return DashedBorder(
      key: const ValueKey('reminder-field'),
      color: c.accentCyan,
      fill: c.surface,
      radius: 12,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_none, size: 16, color: c.accentCyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ReminderStrings.caption.toUpperCase(),
                  style: NexoraText.overline.copyWith(color: c.accentCyan),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  ReminderStrings.deviceTag,
                  key: const ValueKey('reminder-device-tag'),
                  style: NexoraText.label.copyWith(color: c.text2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  key: const ValueKey('reminder-state'),
                  style: NexoraText.bodyStrong.copyWith(color: c.text1),
                ),
              ),
              OutlinedButton(
                key: const ValueKey('reminder-button'),
                onPressed: () => _open(notifier, reminder),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(
                  reminder == null
                      ? ReminderStrings.setReminder
                      : ReminderStrings.changeReminder,
                ),
              ),
              if (reminder != null)
                IconButton(
                  key: const ValueKey('reminder-clear'),
                  tooltip: ReminderStrings.clearReminder,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    service.cancel(widget.taskId);
                    setState(() => _error = null);
                    _toast(ReminderStrings.removed);
                  },
                ),
            ],
          ),
          if (reminder?.state == ReminderState.notified)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  FilledButton(
                    key: const ValueKey('reminder-ack'),
                    onPressed: () {
                      service.acknowledge(widget.taskId);
                    },
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: const Text(ReminderStrings.acknowledge),
                  ),
                  const SizedBox(width: 8),
                  SnoozeMenuButton(
                    buttonKey: const ValueKey('reminder-snooze'),
                    taskId: widget.taskId,
                    service: service,
                    onSnoozed: (error) {
                      setState(() => _error = error);
                      if (error == null) {
                        _toast(ReminderStrings.snoozed);
                      }
                    },
                  ),
                ],
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                key: const ValueKey('reminder-error'),
                style: NexoraText.caption.copyWith(color: c.statusOverdue),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${ReminderStrings.notInSave} ${ReminderStrings.notSynchronized}',
              key: const ValueKey('reminder-device-only'),
              style: NexoraText.caption.copyWith(color: c.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
