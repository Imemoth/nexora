import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_search.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'edit_draft.dart';
import 'nav_selection.dart';
import 'task_visibility.dart';
import 'visible_task_row.dart';
import 'workspace_error.dart';
import 'workspace_transition.dart';

/// What an incoming change did to the task whose edits are still unsaved.
enum IncomingKind { updated, deleted }

/// Raised when synchronization changed or deleted the task the user is editing
/// while the draft holds unsaved edits. Nothing in the draft is lost.
final class IncomingNotice {
  const IncomingNotice(this.kind, [this.overlap = const {}]);

  final IncomingKind kind;

  /// Fields edited locally that also changed incoming (empty for a deletion).
  final Set<String> overlap;
}

/// Why the selected task is not a row of the current list.
enum HiddenReason {
  /// It is not in the selected view or project.
  notInView,

  /// The search text does not match it.
  searchMismatch,

  /// The status filter excludes it.
  statusFiltered,

  /// A parent above it is collapsed.
  collapsedAncestor,
}

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
    this.expansionDefaulted = const {},
    this.draft,
    this.incoming,
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

  /// Parents the default expansion has already been applied to. A parent in
  /// here is never expanded automatically again, so a collapse the user chose
  /// survives rebuilds, refreshes and changes of view, search and filter.
  /// Cleared only when the workspace is loaded afresh.
  final Set<String> expansionDefaulted;

  /// Editable copy of the selected task. Null when nothing is selected.
  final EditDraft? draft;

  /// Set when an incoming change touched the task behind a dirty [draft].
  final IncomingNotice? incoming;

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

  /// Every reason the selected task is not shown in the list (empty when it is
  /// shown or nothing is selected). Each reason has one explicit, non-destructive
  /// way out, offered by the list; nothing is changed on the user's behalf.
  Set<HiddenReason> get hiddenReasons {
    final id = selectedTaskId;
    final task = id == null ? null : tasks[id];
    if (task == null || !selectedTaskHidden) {
      return const {};
    }
    final reasons = <HiddenReason>{};
    if (!inSelection(task, selection, today)) {
      reasons.add(HiddenReason.notInView);
    }
    if (!matchesSearch(task, searchQuery)) {
      reasons.add(HiddenReason.searchMismatch);
    }
    if (statusFilter != null && task.status != statusFilter) {
      reasons.add(HiddenReason.statusFiltered);
    }
    if (reasons.isEmpty) {
      reasons.add(HiddenReason.collapsedAncestor);
    }
    return reasons;
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
    Set<String>? expansionDefaulted,
    EditDraft? draft,
    bool clearDraft = false,
    IncomingNotice? incoming,
    bool clearIncoming = false,
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
      expansionDefaulted: expansionDefaulted ?? this.expansionDefaulted,
      draft: clearDraft ? null : (draft ?? this.draft),
      incoming: clearIncoming || clearDraft
          ? null
          : (incoming ?? this.incoming),
      pending: clearPending ? null : (pending ?? this.pending),
      error: clearError ? null : (error ?? this.error),
      loading: loading ?? this.loading,
      exitReady: exitReady ?? this.exitReady,
      signOutReady: signOutReady ?? this.signOutReady,
    );
  }
}
