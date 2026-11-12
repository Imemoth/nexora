import 'package:flutter/material.dart';

import 'strings/app_strings.dart';
import 'tasks_scope.dart';

/// Right pane. Phase 1 Task 3 shows the selected task read-only; the editor
/// that binds to the draft arrives in Task 5.
class DetailsPane extends StatelessWidget {
  const DetailsPane({super.key});

  @override
  Widget build(BuildContext context) {
    final draft = TasksScope.of(context).state.draft;
    if (draft == null) {
      return Center(child: Text(AppStrings.selectTaskPrompt));
    }
    final textTheme = Theme.of(context).textTheme;
    final due = draft.dueDate;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          draft.title,
          key: const ValueKey('details-title'),
          style: textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        _DetailRow(
          label: AppStrings.fieldStatus,
          value: AppStrings.statusLabel(draft.status),
        ),
        _DetailRow(
          label: AppStrings.fieldPriority,
          value: AppStrings.priorityLabel(draft.priority),
        ),
        _DetailRow(
          label: AppStrings.fieldDue,
          value: due?.toIsoString() ?? AppStrings.noDueDate,
        ),
        _DetailRow(
          label: AppStrings.fieldNotes,
          value: draft.notes.isEmpty ? AppStrings.noNotes : draft.notes,
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(value, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}
