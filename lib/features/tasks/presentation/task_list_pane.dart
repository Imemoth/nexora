import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/application/visible_task_row.dart';

import 'strings/app_strings.dart';
import 'tasks_scope.dart';

/// Center pane: header with the current selection and result count, then the
/// visible task rows. The recursive tree and search field arrive in Task 4.
class TaskListPane extends StatelessWidget {
  const TaskListPane({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final rows = state.visibleRows;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titleFor(state),
                key: const ValueKey('list-title'),
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.taskCount(state.resultCount),
                key: const ValueKey('list-count'),
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text(AppStrings.noTasksHere))
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _TaskRowTile(
                    row: rows[index],
                    selected: rows[index].task.id == state.selectedTaskId,
                    onTap: () => notifier.selectTask(rows[index].task.id),
                  ),
                ),
        ),
      ],
    );
  }

  String _titleFor(WorkspaceState state) {
    return switch (state.selection) {
      SmartViewSelection(:final view) => AppStrings.smartViewLabel(view),
      ProjectSelection(:final projectId) => _projectName(state, projectId),
    };
  }

  String _projectName(WorkspaceState state, String projectId) {
    for (final project in state.projects) {
      if (project.id == projectId) {
        return project.name;
      }
    }
    return '';
  }
}

class _TaskRowTile extends StatelessWidget {
  const _TaskRowTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  final VisibleTaskRow row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('row-${row.task.id}'),
      selected: selected,
      contentPadding: EdgeInsets.only(left: 24 + row.depth * 20.0, right: 24),
      title: Text(row.task.title),
      subtitle: Text(AppStrings.statusLabel(row.task.status)),
      onTap: onTap,
    );
  }
}
