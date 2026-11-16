import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';

import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// Due date with an optional time of day, one full-width row each so the whole
/// date (including the day) is readable at every panel width.
///
/// * The date alone is a genuine date-only deadline: no time is implied.
/// * A time can be added, changed or removed without touching the date.
/// * Clearing the date also removes the time (a time needs a date).
/// * [timeSupported] false (a synchronized workspace, ADR 0004) shows the time
///   row disabled with the reason instead of hiding it.
class DueDateField extends StatelessWidget {
  const DueDateField({
    super.key,
    required this.dueDate,
    required this.dueTime,
    required this.today,
    required this.timeSupported,
    required this.onDateChanged,
    required this.onTimeChanged,
  });

  final CalendarDate? dueDate;
  final DueTime? dueTime;
  final CalendarDate today;
  final bool timeSupported;
  final ValueChanged<CalendarDate?> onDateChanged;
  final ValueChanged<DueTime?> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final hasDate = dueDate != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.fieldDueDate,
          style: NexoraText.label.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 4),
        _ValueRow(
          buttonKey: const ValueKey('due-date-button'),
          clearKey: const ValueKey('due-date-clear'),
          icon: Icons.event,
          text: dueDate?.toIsoString() ?? AppStrings.noDueDate,
          muted: !hasDate,
          clearTooltip: AppStrings.clearDueDate,
          onPressed: () => _pickDate(context),
          onClear: hasDate ? () => onDateChanged(null) : null,
        ),
        const SizedBox(height: 10),
        Text(
          AppStrings.fieldDueTime,
          style: NexoraText.label.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 4),
        _ValueRow(
          buttonKey: const ValueKey('due-time-button'),
          clearKey: const ValueKey('due-time-clear'),
          icon: Icons.schedule,
          text: dueTime == null
              ? AppStrings.noDueTime
              : AppStrings.dueTimeLabel(dueTime!),
          muted: dueTime == null,
          clearTooltip: AppStrings.clearDueTime,
          onPressed: hasDate && timeSupported ? () => _pickTime(context) : null,
          onClear: dueTime != null && timeSupported
              ? () => onTimeChanged(null)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          key: const ValueKey('due-help'),
          !timeSupported
              ? AppStrings.dueTimeLocalOnly
              : !hasDate
              ? AppStrings.dueTimeNeedsDate
              : '${AppStrings.dueTimeHelp} ${AppStrings.clearDueDateHelp}',
          style: NexoraText.caption.copyWith(color: c.textMuted),
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final initial = dueDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onDateChanged(CalendarDate.fromDateTime(picked));
    }
  }

  Future<void> _pickTime(BuildContext context) async {
    final initial = dueTime ?? const DueTime(9, 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
      initialEntryMode: TimePickerEntryMode.input,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) {
      onTimeChanged(DueTime(picked.hour, picked.minute));
    }
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.buttonKey,
    required this.clearKey,
    required this.icon,
    required this.text,
    required this.muted,
    required this.clearTooltip,
    required this.onPressed,
    required this.onClear,
  });

  final Key buttonKey;
  final Key clearKey;
  final IconData icon;
  final String text;
  final bool muted;
  final String clearTooltip;
  final VoidCallback? onPressed;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              backgroundColor: c.surface,
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            label: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexoraText.body.copyWith(
                color: muted ? c.textMuted : c.text1,
              ),
            ),
          ),
        ),
        // Keeps the rows aligned whether or not there is something to clear.
        SizedBox(
          width: 40,
          child: onClear == null
              ? null
              : IconButton(
                  key: clearKey,
                  tooltip: clearTooltip,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClear,
                ),
        ),
      ],
    );
  }
}
