import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';

import 'strings/app_strings.dart';
import 'sort_menu.dart';
import 'task_row.dart';
import 'task_search_field.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';

/// Center pane: header, search and sort controls, then the task tree.
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
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: TaskSearchField(
                  query: state.searchQuery,
                  onChanged: notifier.search,
                ),
              ),
              const SizedBox(width: 8),
              SortMenu(sort: state.sort, onSelected: notifier.sort),
            ],
          ),
        ),
        if (state.selectedTaskHidden)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              AppStrings.selectedTaskHidden,
              key: const ValueKey('hidden-notice'),
              style: textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? _EmptyList(
                  state: state,
                  onClearSearch: () => notifier.search(''),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return TaskRow(
                      row: row,
                      selected: row.task.id == state.selectedTaskId,
                      onSelect: () => notifier.selectTask(row.task.id),
                      onToggle: () => notifier.toggleExpanded(row.task.id),
                    );
                  },
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

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.state, required this.onClearSearch});

  final WorkspaceState state;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    if (state.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.noSearchMatches),
            TextButton(
              onPressed: onClearSearch,
              child: const Text(AppStrings.clearSearch),
            ),
          ],
        ),
      );
    }
    if (state.selection is ProjectSelection) {
      return const Center(child: Text(AppStrings.emptyProject));
    }
    return const Center(child: Text(AppStrings.noTasksHere));
  }
}
