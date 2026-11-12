import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';

import 'strings/app_strings.dart';

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
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(AppStrings.fieldDue, style: textTheme.labelMedium),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('due-date-button'),
                onPressed: () => _pick(context),
                icon: const Icon(Icons.event),
                label: Text(dueDate?.toIsoString() ?? AppStrings.noDueDate),
              ),
            ),
            if (dueDate != null)
              IconButton(
                key: const ValueKey('due-date-clear'),
                tooltip: AppStrings.clearDueDate,
                icon: const Icon(Icons.clear),
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
