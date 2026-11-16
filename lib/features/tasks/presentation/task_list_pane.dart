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
          // Search has a row of its own. Filters and sort sit below it and wrap
          // cleanly: the sort control drops to its own line before anything
          // overlaps or leaves the pane.
          SizedBox(
            height: 38,
            child: TaskSearchField(
              query: state.searchQuery,
              onChanged: notifier.search,
              focusNode: keyboard.search,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            key: const ValueKey('list-tools'),
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const StatusFilterBar(),
              SortMenu(sort: state.sort, onSelected: notifier.sort),
            ],
          ),
          if (state.selectedTaskHidden)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _HiddenNotice(state: state, notifier: notifier),
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
                            return _TaskRows(
                              rows: rows,
                              state: state,
                              notifier: notifier,
                              keyboard: keyboard,
                              labels: labels,
                              focused: keyboard.list.hasPrimaryFocus,
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

/// Says that the selected task is not a row of this list, and why, and offers one
/// explicit action per cause. It never changes anything by itself: the user's
/// search, filter and view stay until they choose otherwise.
class _HiddenNotice extends StatelessWidget {
  const _HiddenNotice({required this.state, required this.notifier});

  final WorkspaceState state;
  final TasksNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final c = NexoraColors.of(context);
    final reasons = state.hiddenReasons;
    final task = state.tasks[state.selectedTaskId];
    final project = task == null
        ? null
        : state.projects.where((p) => p.id == task.projectId).firstOrNull;
    final actions = <Widget>[
      if (reasons.contains(HiddenReason.notInView) && task != null)
        _NoticeAction(
          key: const ValueKey('reveal-project'),
          label: AppStrings.revealShowInProject(project?.name ?? ''),
          onPressed: () => notifier.selectProject(task.projectId),
        ),
      if (reasons.contains(HiddenReason.searchMismatch))
        _NoticeAction(
          key: const ValueKey('reveal-clear-search'),
          label: AppStrings.revealClearSearch,
          onPressed: () => notifier.search(''),
        ),
      if (reasons.contains(HiddenReason.statusFiltered))
        _NoticeAction(
          key: const ValueKey('reveal-clear-filter'),
          label: AppStrings.revealShowAllStatuses,
          onPressed: () => notifier.filterStatus(null),
        ),
      if (reasons.contains(HiddenReason.collapsedAncestor) && task != null)
        _NoticeAction(
          key: const ValueKey('reveal-expand'),
          label: AppStrings.revealExpandParents,
          onPressed: () => notifier.expandAncestorsOf(task.id),
        ),
    ];
    return DashedBorder(
      color: c.borderStrong,
      radius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            AppStrings.selectedTaskHidden,
            key: const ValueKey('hidden-notice'),
            style: NexoraText.caption.copyWith(color: c.text2),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _NoticeAction extends StatelessWidget {
  const _NoticeAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(label),
    );
  }
}

/// The rows of the list. Keeps the selected row in view: when the selection
/// changes (a click, the arrow keys, or revealing a related subtask) the list
/// scrolls just enough to show it, including a row that has not been built yet.
class _TaskRows extends StatefulWidget {
  const _TaskRows({
    required this.rows,
    required this.state,
    required this.notifier,
    required this.keyboard,
    required this.labels,
    required this.focused,
  });

  final List<VisibleTaskRow> rows;
  final WorkspaceState state;
  final TasksNotifier notifier;
  final TaskKeyboardFocus keyboard;
  final Map<String, String> labels;
  final bool focused;

  @override
  State<_TaskRows> createState() => _TaskRowsState();
}

class _TaskRowsState extends State<_TaskRows> {
  final ScrollController _controller = ScrollController();

  @override
  void didUpdateWidget(covariant _TaskRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.state.selectedTaskId;
    final rowsChanged =
        oldWidget.rows.length != widget.rows.length ||
        oldWidget.state.expandedTaskIds != widget.state.expandedTaskIds;
    if (id != null && (id != oldWidget.state.selectedTaskId || rowsChanged)) {
      _scrollTo(id);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The element of the built row of [id], found by its `row-<id>` key. (A
  /// `GlobalKey` per row would be simpler but breaks Tab traversal in the list.)
  BuildContext? _contextOf(String id) {
    BuildContext? found;
    void visit(Element element) {
      if (found != null) {
        return;
      }
      if (element.widget.key == ValueKey('row-$id')) {
        found = element;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found;
  }

  /// Shows the row of [id]. A row far outside the built range is first brought
  /// near by an estimate, then centred exactly once it exists.
  void _scrollTo(String id, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      final index = widget.rows.indexWhere((r) => r.task.id == id);
      if (index < 0) {
        return;
      }
      final rowContext = _contextOf(id);
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          alignment: 0.5,
          duration: const Duration(milliseconds: 120),
        );
        return;
      }
      if (attempt >= 6) {
        return;
      }
      final position = _controller.position;
      // The list estimates its total length from the rows it has built, so the
      // average row height follows from the scroll extent. Aim at the row's
      // middle; the next attempt centres it exactly once it is built.
      final perRow =
          (position.maxScrollExtent + position.viewportDimension) /
          widget.rows.length;
      final target = (index * perRow - position.viewportDimension / 2).clamp(
        0.0,
        position.maxScrollExtent,
      );
      _controller.jumpTo(target);
      _scrollTo(id, attempt: attempt + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.all(6),
      itemCount: widget.rows.length,
      itemBuilder: (context, index) {
        final row = widget.rows[index];
        return TaskRow(
          row: row,
          today: state.today,
          selected: row.task.id == state.selectedTaskId,
          listFocused: widget.focused,
          contextLabel: widget.labels[row.task.id],
          onSelect: () {
            widget.keyboard.list.requestFocus();
            widget.notifier.selectTask(row.task.id);
          },
          onToggle: () => widget.notifier.toggleExpanded(row.task.id),
        );
      },
    );
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
