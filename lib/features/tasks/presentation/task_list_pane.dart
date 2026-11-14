import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';

import 'dashboard_header.dart';
import 'keymap.dart';
import 'quick_add_field.dart';
import 'status_filter_bar.dart';
import 'tasks_notifier.dart';
import 'theme/nexora_colors.dart';
import 'theme_selector.dart';
import 'keyboard_actions.dart';
import 'strings/app_strings.dart';
import 'sort_menu.dart';
import 'task_row.dart';
import 'task_search_field.dart';
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
    final keyboard = TaskKeyboardFocus.of(notifier);

    return KeymapScope(
      listNavigation: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
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
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      const ThemeSelector(),
                      FilledButton.icon(
                        key: const ValueKey('new-task'),
                        onPressed: () => openCreateTask(context, notifier),
                        icon: const Icon(Icons.add),
                        label: const Text(AppStrings.newTaskAction),
                      ),
                    ],
                  ),
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
                    focusNode: keyboard.search,
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
            child: Focus(
              focusNode: keyboard.list,
              autofocus: true,
              child: ListenableBuilder(
                listenable: keyboard.list,
                builder: (context, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      width: 2,
                      color: keyboard.list.hasPrimaryFocus
                          ? NexoraColors.of(context).accentCyan
                          : Colors.transparent,
                    ),
                  ),
                  child: child,
                ),
                // The dashboard, filter chips and quick add scroll with the
                // list, so they never take room from the rows. They stay in the
                // empty state too, so a filter can always be cleared.
                child: rows.isEmpty
                    ? ListView(
                        children: [
                          _listHeader(state, notifier),
                          SizedBox(
                            height: 240,
                            child: _EmptyList(
                              state: state,
                              onClearSearch: () => notifier.search(''),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: rows.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _listHeader(state, notifier);
                          }
                          final row = rows[index - 1];
                          return TaskRow(
                            row: row,
                            today: state.today,
                            selected: row.task.id == state.selectedTaskId,
                            onSelect: () {
                              keyboard.list.requestFocus();
                              notifier.selectTask(row.task.id);
                            },
                            onToggle: () =>
                                notifier.toggleExpanded(row.task.id),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHeader(WorkspaceState state, TasksNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: DashboardHeader(state: state),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: StatusFilterBar(state: state, notifier: notifier),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: QuickAddField(notifier: notifier),
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
    // A failed load is reported as an error, not as an empty list.
    if (state.error == WorkspaceError.loadFailed) {
      return const Center(child: Text(AppStrings.errorLoadFailed));
    }
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
