import 'package:flutter/material.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/visible_task_row.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';

import 'dashed_border.dart';
import 'keyboard_actions.dart';
import 'keycap.dart';
import 'keymap.dart';
import 'quick_add_field.dart';
import 'sort_menu.dart';
import 'status_filter_bar.dart';
import 'strings/app_strings.dart';
import 'task_row.dart';
import 'task_search_field.dart';
import 'tasks_notifier.dart';
import 'tasks_scope.dart';
import 'theme/nexora_colors.dart';

/// Center pane: header, tools, then the task tree in a card.
class TaskListPane extends StatelessWidget {
  const TaskListPane({super.key});

  @override
  Widget build(BuildContext context) {
    final notifier = TasksScope.of(context);
    final state = notifier.state;
    final rows = state.visibleRows;
    final c = NexoraColors.of(context);
    final keyboard = TaskKeyboardFocus.of(notifier);
    final labels = _contextLabels(state, rows);

    return KeymapScope(
      listNavigation: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(state: state, notifier: notifier),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusFilterBar(),
              SizedBox(
                width: 260,
                height: 38,
                child: TaskSearchField(
                  query: state.searchQuery,
                  onChanged: notifier.search,
                  focusNode: keyboard.search,
                ),
              ),
              SortMenu(sort: state.sort, onSelected: notifier.sort),
            ],
          ),
          if (state.selectedTaskHidden)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DashedBorder(
                color: c.borderStrong,
                radius: 8,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  AppStrings.selectedTaskHidden,
                  key: const ValueKey('hidden-notice'),
                  style: NexoraText.caption.copyWith(color: c.text2),
                ),
              ),
            ),
          const SizedBox(height: 14),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Column(
                  children: [
                    QuickAddField(notifier: notifier),
                    Expanded(
                      child: Focus(
                        focusNode: keyboard.list,
                        autofocus: true,
                        child: ListenableBuilder(
                          listenable: keyboard.list,
                          builder: (context, _) {
                            if (rows.isEmpty) {
                              return _EmptyList(
                                state: state,
                                onClearSearch: () => notifier.search(''),
                                onShowAll: () => notifier.filterStatus(null),
                                onNewTask: () =>
                                    openCreateTask(context, notifier),
                              );
                            }
                            final focused = keyboard.list.hasPrimaryFocus;
                            return ListView.builder(
                              padding: const EdgeInsets.all(6),
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final row = rows[index];
                                return TaskRow(
                                  row: row,
                                  today: state.today,
                                  selected: row.task.id == state.selectedTaskId,
                                  listFocused: focused,
                                  contextLabel: labels[row.task.id],
                                  onSelect: () {
                                    keyboard.list.requestFocus();
                                    notifier.selectTask(row.task.id);
                                  },
                                  onToggle: () =>
                                      notifier.toggleExpanded(row.task.id),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Context text for rows that stand outside their own place in the tree. In a
  /// smart view it is the project, then " › " and the parent title when the
  /// parent row is not itself shown. In a project only a parent that is not
  /// shown (a search hides it) is named. Presentation only: it never changes
  /// which rows appear.
  Map<String, String> _contextLabels(
    WorkspaceState state,
    List<VisibleTaskRow> rows,
  ) {
    final shown = {for (final row in rows) row.task.id};
    final projects = {for (final p in state.projects) p.id: p.name};
    final inView = state.selection is SmartViewSelection;
    final labels = <String, String>{};
    for (final row in rows) {
      final task = row.task;
      final parentId = task.parentId;
      final parent = parentId == null ? null : state.tasks[parentId];
      final parentHidden = parent != null && !shown.contains(parent.id);
      final parts = <String>[];
      if (inView) {
        final project = projects[task.projectId];
        if (project != null) {
          parts.add(project);
        }
      }
      if (parentHidden) {
        parts.add(parent.title);
      }
      if (parts.isNotEmpty) {
        labels[task.id] = parts.join(AppStrings.contextSeparator);
      }
    }
    return labels;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.notifier});

  final WorkspaceState state;
  final TasksNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final overdue = state.overdueCount;
    final title = _titleFor(state);
    final breadcrumb = switch (state.selection) {
      SmartViewSelection() => AppStrings.breadcrumbView(title),
      _ => AppStrings.breadcrumbProject(title),
    };
    final style = NexoraText.body.copyWith(color: c.text2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                breadcrumb,
                style: NexoraText.caption.copyWith(color: c.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                key: const ValueKey('list-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexoraText.titlePage.copyWith(color: c.text1),
              ),
              const SizedBox(height: 2),
              Wrap(
                children: [
                  Text(
                    AppStrings.taskCount(state.resultCount),
                    key: const ValueKey('list-count'),
                    style: style,
                  ),
                  Text(AppStrings.summarySeparator, style: style),
                  Text(
                    AppStrings.summaryLineDone(state.doneCount),
                    style: style,
                  ),
                  Text(AppStrings.summarySeparator, style: style),
                  Text(
                    AppStrings.summaryLineOverdue(overdue),
                    key: const ValueKey('list-overdue'),
                    style: overdue > 0
                        ? style.copyWith(
                            color: c.statusOverdue,
                            fontWeight: FontWeight.w700,
                          )
                        : style,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          key: const ValueKey('new-task'),
          onPressed: () => openCreateTask(context, notifier),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 18),
              const SizedBox(width: 6),
              const Text(AppStrings.newTaskAction),
              const SizedBox(width: 10),
              Keycap('Ctrl N', onFill: true),
            ],
          ),
        ),
      ],
    );
  }

  String _titleFor(WorkspaceState state) {
    return switch (state.selection) {
      SmartViewSelection(:final view) => AppStrings.smartViewLabel(view),
      ProjectSelection(:final projectId) => _projectName(state, projectId),
      DashboardSelection() => AppStrings.dashboardTitle,
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
  const _EmptyList({
    required this.state,
    required this.onClearSearch,
    required this.onShowAll,
    required this.onNewTask,
  });

  final WorkspaceState state;
  final VoidCallback onClearSearch;
  final VoidCallback onShowAll;
  final VoidCallback onNewTask;

  @override
  Widget build(BuildContext context) {
    // A failed load is reported as an error, not as an empty list.
    if (state.error == WorkspaceError.loadFailed) {
      return const _EmptyMessage(text: AppStrings.errorLoadFailed);
    }
    if (state.searchQuery.isNotEmpty) {
      return _EmptyMessage(
        text: AppStrings.noSearchMatches,
        actionLabel: AppStrings.clearSearch,
        onAction: onClearSearch,
      );
    }
    if (state.statusFilter != null) {
      return _EmptyMessage(
        text: AppStrings.noTasksMatchFilter,
        actionLabel: AppStrings.showAll,
        onAction: onShowAll,
      );
    }
    if (state.selection is ProjectSelection) {
      return _EmptyMessage(
        text: AppStrings.emptyProject,
        actionLabel: AppStrings.newTaskAction,
        onAction: onNewTask,
      );
    }
    return const _EmptyMessage(text: AppStrings.noTasksHere);
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: NexoraText.body.copyWith(color: c.text2)),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
