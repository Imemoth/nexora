import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'edit_draft.dart';
import 'nav_selection.dart';
import 'task_visibility.dart';
import 'visible_task_row.dart';
import 'workspace_error.dart';
import 'workspace_transition.dart';

/// Immutable snapshot of everything the presentation shows.
final class WorkspaceState {
  const WorkspaceState({
    required this.today,
    this.projects = const [],
    this.tasks = const {},
    this.selection = const SmartViewSelection(SmartView.all),
    this.searchQuery = '',
    this.sort = TaskSort.position,
    this.statusFilter,
    this.selectedTaskId,
    this.expandedTaskIds = const {},
    this.draft,
    this.pending,
    this.error,
    this.loading = false,
    this.exitReady = false,
    this.signOutReady = false,
  });

  factory WorkspaceState.initial(CalendarDate today) {
    return WorkspaceState(today: today);
  }

  /// The local date used for smart views and counts.
  final CalendarDate today;
  final List<Project> projects;

  /// All tasks by id, regardless of filters.
  final Map<String, Task> tasks;
  final NavSelection selection;
  final String searchQuery;
  final TaskSort sort;

  /// Shows only tasks with this status. Null shows every status. Like sort, it
  /// never touches the draft and is never gated.
  final TaskStatus? statusFilter;

  /// The selected task. Always equal to [draft]'s task id when both are set.
  final String? selectedTaskId;
  final Set<String> expandedTaskIds;

  /// Editable copy of the selected task. Null when nothing is selected.
  final EditDraft? draft;

  /// Non-null while the unsaved-change gate is open.
  final PendingTransition? pending;
  final WorkspaceError? error;
  final bool loading;

  /// Set once the gate resolves to exit. The presentation then closes the app.
  final bool exitReady;

  /// Set once the gate resolves to sign out. The presentation then signs out.
  final bool signOutReady;

  /// Flattened rows for the current selection, search, sort and expansion.
  List<VisibleTaskRow> get visibleRows {
    return buildVisibleRows(
      tasks: tasks,
      selection: selection,
      query: searchQuery,
      sort: sort,
      expandedIds: expandedTaskIds,
      today: today,
      statusFilter: statusFilter,
    );
  }

  /// True when the selected task is hidden by a collapsed parent.
  bool get selectedTaskHidden {
    final id = selectedTaskId;
    if (id == null) {
      return false;
    }
    return !visibleRows.any((row) => row.task.id == id);
  }

  /// Number of tasks in [selection], ignoring the search query.
  int countFor(NavSelection selection) {
    return tasks.values
        .where((task) => inSelection(task, selection, today))
        .length;
  }

  /// Number of tasks in the current selection that match the search query,
  /// including children hidden under collapsed parents.
  int get resultCount {
    return tasks.values
        .where((task) => matchesFilter(task, selection, searchQuery, today))
        .length;
  }

  /// The tasks of the current selection and search, before the status filter.
  List<Task> get scopedTasks => [
    for (final task in tasks.values)
      if (matchesFilter(task, selection, searchQuery, today)) task,
  ];

  /// Number of scoped tasks with [status] (null: every status), for the filter
  /// chips.
  int statusCount(TaskStatus? status) {
    final scoped = scopedTasks;
    return status == null
        ? scoped.length
        : scoped.where((task) => task.status == status).length;
  }

  /// Scoped tasks that are done.
  int get doneCount =>
      scopedTasks.where((task) => task.status == TaskStatus.done).length;

  /// Scoped tasks that are overdue (open and due before today).
  int get overdueCount => scopedTasks
      .where((task) => matchesSmartView(task, SmartView.overdue, today))
      .length;

  WorkspaceState copyWith({
    CalendarDate? today,
    List<Project>? projects,
    Map<String, Task>? tasks,
    NavSelection? selection,
    String? searchQuery,
    TaskSort? sort,
    TaskStatus? statusFilter,
    bool clearStatusFilter = false,
    String? selectedTaskId,
    bool clearSelectedTask = false,
    Set<String>? expandedTaskIds,
    EditDraft? draft,
    bool clearDraft = false,
    PendingTransition? pending,
    bool clearPending = false,
    WorkspaceError? error,
    bool clearError = false,
    bool? loading,
    bool? exitReady,
    bool? signOutReady,
  }) {
    return WorkspaceState(
      today: today ?? this.today,
      projects: projects ?? this.projects,
      tasks: tasks ?? this.tasks,
      selection: selection ?? this.selection,
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      statusFilter: clearStatusFilter
          ? null
          : (statusFilter ?? this.statusFilter),
      selectedTaskId: clearSelectedTask
          ? null
          : (selectedTaskId ?? this.selectedTaskId),
      expandedTaskIds: expandedTaskIds ?? this.expandedTaskIds,
      draft: clearDraft ? null : (draft ?? this.draft),
      pending: clearPending ? null : (pending ?? this.pending),
      error: clearError ? null : (error ?? this.error),
      loading: loading ?? this.loading,
      exitReady: exitReady ?? this.exitReady,
      signOutReady: signOutReady ?? this.signOutReady,
    );
  }
}
