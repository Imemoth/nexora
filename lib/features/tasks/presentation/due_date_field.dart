import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';

import 'package:nexora/app/theme.dart';

import 'strings/app_strings.dart';
import 'theme/nexora_colors.dart';

/// Date-only due date. Shows the ISO date, opens a date picker, and clears
/// the date. No time or time zone is ever stored.
class DueDateField extends StatelessWidget {
  const DueDateField({
    super.key,
    required this.dueDate,
    required this.today,
    required this.onChanged,
  });

  final CalendarDate? dueDate;
  final CalendarDate today;
  final ValueChanged<CalendarDate?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.fieldDue,
          style: NexoraText.label.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('due-date-button'),
                onPressed: () => _pick(context),
                icon: const Icon(Icons.event, size: 18),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  backgroundColor: c.surface,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                label: Text(
                  dueDate?.toIsoString() ?? AppStrings.noDueDate,
                  overflow: TextOverflow.ellipsis,
                  style: NexoraText.body.copyWith(
                    color: dueDate == null ? c.textMuted : c.text1,
                  ),
                ),
              ),
            ),
            if (dueDate != null)
              IconButton(
                key: const ValueKey('due-date-clear'),
                tooltip: AppStrings.clearDueDate,
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final initial = dueDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      onChanged(CalendarDate.fromDateTime(picked));
    }
  }
}
