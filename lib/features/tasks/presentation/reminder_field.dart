import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import 'dashed_border.dart';
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
  bool _editing = false;
  final TextEditingController _date = TextEditingController();
  final TextEditingController _time = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    super.dispose();
  }

  void _toast(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  /// Opens the inline editor with the existing reminder's date and time,
  /// otherwise tomorrow at 09:00.
  void _open(RemindersNotifier notifier, Reminder? current) {
    final service = notifier.service;
    final now = service.clock.toLocal(service.clock.nowUtc());
    final initial =
        current?.remindAt ??
        LocalWallTime.fromDateTime(
          DateTime(now.year, now.month, now.day + 1, 9),
        );
    _date.text =
        '${initial.year.toString().padLeft(4, '0')}-'
        '${_two(initial.month)}-${_two(initial.day)}';
    _time.text = '${_two(initial.hour)}:${_two(initial.minute)}';
    setState(() {
      _editing = true;
      _error = null;
    });
  }

  void _close() => setState(() {
    _editing = false;
    _error = null;
  });

  /// One `setReminder` call with the combined wall time, exactly as the two
  /// pickers did before. An error keeps the editor open.
  void _submit(RemindersNotifier notifier) {
    final date = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$')
        .firstMatch(_date.text.trim());
    final time = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    final wall = date == null || time == null
        ? null
        : LocalWallTime.tryParse(
            '${date.group(1)}-${date.group(2)}-${date.group(3)}'
            'T${_two(int.parse(time.group(1)!))}:${time.group(2)}',
          );
    if (wall == null) {
      setState(() => _error = ReminderStrings.errorFormat);
      return;
    }
    final error = notifier.service.setReminder(widget.taskId, wall);
    if (error != null) {
      setState(() => _error = ReminderStrings.errorMessage(error));
      return;
    }
    setState(() {
      _editing = false;
      _error = null;
    });
    _toast(ReminderStrings.saved);
  }

  Future<void> _pickDate(RemindersNotifier notifier) async {
    final service = notifier.service;
    final now = service.clock.toLocal(service.clock.nowUtc());
    final parsed = DateTime.tryParse(_date.text.trim());
    final picked = await showDatePicker(
      context: context,
      helpText: ReminderStrings.pickDate,
      initialDate:
          parsed == null ||
              parsed.isBefore(DateTime(now.year, now.month, now.day))
          ? DateTime(now.year, now.month, now.day)
          : parsed,
      // Dates before today cannot be picked.
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    _date.text =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${_two(picked.month)}-${_two(picked.day)}';
    setState(() {});
  }

  Future<void> _pickTime() async {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    final picked = await showTimePicker(
      context: context,
      helpText: ReminderStrings.pickTime,
      initialTime: TimeOfDay(
        hour: match == null ? 9 : int.parse(match.group(1)!) % 24,
        minute: match == null ? 0 : int.parse(match.group(2)!) % 60,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    _time.text = '${_two(picked.hour)}:${_two(picked.minute)}';
    setState(() {});
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
                onPressed: () =>
                    _editing ? _close() : _open(notifier, reminder),
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
                    setState(() {
                      _error = null;
                      _editing = false;
                    });
                    _toast(ReminderStrings.removed);
                  },
                ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 10),
            CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): _close,
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('reminder-date'),
                      controller: _date,
                      decoration: InputDecoration(
                        labelText: ReminderStrings.pickDate,
                        hintText: ReminderStrings.dateHint,
                        suffixIcon: IconButton(
                          tooltip: ReminderStrings.pickDateTooltip,
                          icon: const Icon(Icons.event, size: 18),
                          onPressed: () => _pickDate(notifier),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('reminder-time'),
                      controller: _time,
                      onSubmitted: (_) => _submit(notifier),
                      decoration: InputDecoration(
                        labelText: ReminderStrings.pickTime,
                        hintText: ReminderStrings.timeHint,
                        suffixIcon: IconButton(
                          tooltip: ReminderStrings.pickTimeTooltip,
                          icon: const Icon(Icons.schedule, size: 18),
                          onPressed: _pickTime,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  key: const ValueKey('reminder-cancel'),
                  onPressed: _close,
                  child: const Text(ReminderStrings.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('reminder-submit'),
                  onPressed: () => _submit(notifier),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text(ReminderStrings.setReminder),
                ),
              ],
            ),
          ],
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
