import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/reminder_presets.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import 'reminders_notifier.dart';
import 'strings/reminder_strings.dart';
import 'theme/nexora_colors.dart';

/// Opens the one modal for setting or changing the reminder of [taskId].
/// Resolves to true when a reminder was saved; Cancel (or Escape) saves
/// nothing and resolves to null.
Future<bool?> showReminderDialog(
  BuildContext context, {
  required RemindersNotifier notifier,
  required String taskId,
  Reminder? current,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        ReminderDialog(notifier: notifier, taskId: taskId, current: current),
  );
}

enum _Choice { oneHour, twoHours, fiveHours, day, custom }

/// Presets resolve against the current time and show the concrete date and
/// time before the user confirms. The custom choice takes a date and an hour.
/// The reminder is device-local and saved at once; the dialog says so.
class ReminderDialog extends StatefulWidget {
  const ReminderDialog({
    super.key,
    required this.notifier,
    required this.taskId,
    this.current,
  });

  final RemindersNotifier notifier;
  final String taskId;
  final Reminder? current;

  @override
  State<ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<ReminderDialog> {
  final TextEditingController _date = TextEditingController();
  final TextEditingController _time = TextEditingController();
  late _Choice _choice;
  String? _error;

  ReminderClock get _clock => widget.notifier.service.clock;

  static ReminderPreset? _presetOf(_Choice choice) => switch (choice) {
    _Choice.oneHour => ReminderPreset.inOneHour,
    _Choice.twoHours => ReminderPreset.inTwoHours,
    _Choice.fiveHours => ReminderPreset.inFiveHours,
    _Choice.day => ReminderPreset.inTwentyFourHours,
    _Choice.custom => null,
  };

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  void initState() {
    super.initState();
    final existing = widget.current?.remindAt;
    if (existing != null) {
      _choice = _Choice.custom;
      _fill(existing);
    } else {
      _choice = _Choice.oneHour;
      final tomorrow = _clock.toLocal(
        _clock.nowUtc().add(const Duration(days: 1)),
      );
      _fill(LocalWallTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0));
    }
  }

  void _fill(LocalWallTime wall) {
    _date.text =
        '${wall.year.toString().padLeft(4, '0')}-${_two(wall.month)}-${_two(wall.day)}';
    _time.text = '${_two(wall.hour)}:${_two(wall.minute)}';
  }

  @override
  void dispose() {
    _date.dispose();
    _time.dispose();
    super.dispose();
  }

  /// The wall time the current choice means right now, or null for an
  /// incomplete custom entry.
  LocalWallTime? _resolved() {
    final preset = _presetOf(_choice);
    return preset != null
        ? presetWallTime(_clock, preset)
        : parseCustomWallTime(_date.text, _time.text);
  }

  void _select(_Choice choice) => setState(() {
    _choice = choice;
    _error = null;
  });

  void _confirm() {
    final wall = _resolved();
    if (wall == null) {
      setState(() => _error = ReminderStrings.errorFormat);
      return;
    }
    final error = widget.notifier.service.setReminder(widget.taskId, wall);
    if (error != null) {
      setState(() => _error = ReminderStrings.errorMessage(error));
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _pickDate() async {
    final now = _clock.toLocal(_clock.nowUtc());
    final today = DateTime(now.year, now.month, now.day);
    final parsed = DateTime.tryParse(_date.text.trim());
    final picked = await showDatePicker(
      context: context,
      helpText: ReminderStrings.pickDate,
      initialDate: parsed == null || parsed.isBefore(today) ? today : parsed,
      firstDate: today,
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _date.text =
          '${picked.year.toString().padLeft(4, '0')}-${_two(picked.month)}-${_two(picked.day)}';
      _error = null;
    });
  }

  Future<void> _pickTime() async {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_time.text.trim());
    final picked = await showTimePicker(
      context: context,
      helpText: ReminderStrings.pickTime,
      initialEntryMode: TimePickerEntryMode.input,
      initialTime: TimeOfDay(
        hour: match == null ? 9 : int.parse(match.group(1)!) % 24,
        minute: match == null ? 0 : int.parse(match.group(2)!) % 60,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _time.text = '${_two(picked.hour)}:${_two(picked.minute)}';
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final resolved = _resolved();
    return AlertDialog(
      key: const ValueKey('reminder-dialog'),
      title: Text(
        widget.current == null
            ? ReminderStrings.dialogTitle
            : ReminderStrings.dialogTitleChange,
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<_Choice>(
                groupValue: _choice,
                onChanged: (value) {
                  if (value != null) {
                    _select(value);
                  }
                },
                child: Column(
                  children: [
                    for (final choice in _Choice.values)
                      _ChoiceTile(
                        key: ValueKey('reminder-choice-${choice.name}'),
                        choice: choice,
                        label: _label(choice),
                        detail: _presetOf(choice) == null
                            ? null
                            : ReminderStrings.friendlyWhen(
                                presetWallTime(_clock, _presetOf(choice)!),
                              ),
                      ),
                  ],
                ),
              ),
              if (_choice == _Choice.custom) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('reminder-date'),
                        controller: _date,
                        onChanged: (_) => setState(() => _error = null),
                        decoration: InputDecoration(
                          labelText: ReminderStrings.customDateLabel,
                          hintText: ReminderStrings.dateHint,
                          suffixIcon: IconButton(
                            tooltip: ReminderStrings.pickDateTooltip,
                            icon: const Icon(Icons.event, size: 18),
                            onPressed: _pickDate,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: const ValueKey('reminder-time'),
                        controller: _time,
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) => _confirm(),
                        decoration: InputDecoration(
                          labelText: ReminderStrings.customTimeLabel,
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
              ],
              const SizedBox(height: 12),
              Text(
                resolved == null
                    ? ReminderStrings.errorCustomIncomplete
                    : '${ReminderStrings.willRemindAt}: '
                          '${ReminderStrings.friendlyWhen(resolved)}',
                key: const ValueKey('reminder-resolved'),
                style: NexoraText.bodyStrong.copyWith(color: c.text1),
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
              const SizedBox(height: 10),
              Text(
                ReminderStrings.dialogDeviceNote,
                key: const ValueKey('reminder-device-only'),
                style: NexoraText.caption.copyWith(color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('reminder-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(ReminderStrings.cancel),
        ),
        FilledButton(
          key: const ValueKey('reminder-submit'),
          onPressed: _confirm,
          child: const Text(ReminderStrings.setReminder),
        ),
      ],
    );
  }

  String _label(_Choice choice) => switch (choice) {
    _Choice.oneHour => ReminderStrings.presetInOneHour,
    _Choice.twoHours => ReminderStrings.presetInTwoHours,
    _Choice.fiveHours => ReminderStrings.presetInFiveHours,
    _Choice.day => ReminderStrings.presetIn24Hours,
    _Choice.custom => ReminderStrings.presetCustom,
  };
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.choice,
    required this.label,
    required this.detail,
  });

  final _Choice choice;
  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return RadioListTile<_Choice>(
      value: choice,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: NexoraText.body.copyWith(color: c.text1)),
      secondary: detail == null
          ? null
          : Text(detail!, style: NexoraText.caption.copyWith(color: c.text2)),
    );
  }
}
