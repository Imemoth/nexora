import 'dart:async';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_creation_rules.dart';
import 'package:nexora/features/tasks/domain/task_deletion.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_search.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/domain/task_validation.dart';

import 'edit_draft.dart';
import 'nav_selection.dart';
import 'repository_exception.dart';
import 'task_repository.dart';
import 'task_visibility.dart';
import 'workspace_error.dart';
import 'workspace_state.dart';
import 'workspace_transition.dart';

/// The Phase 1 task workspace: selection, search, sort, expansion, the edit
/// draft and the unsaved-change gate.
///
/// Pure Dart. Nothing here imports Flutter or a persistence package. Every
/// navigation that could discard a dirty draft goes through [_request], so
/// the gate covers all entry points.
final class TaskWorkspace {
  TaskWorkspace({
    required this.repository,
    required this.clock,
    required this.ids,
    this.dueTimeSupported = true,
  }) : _state = WorkspaceState.initial(clock.today());

  final TaskRepository repository;
  final Clock clock;
  final IdGenerator ids;

  /// Whether a due date may carry a time of day. False for a synchronized
  /// workspace until the hosted schema can store it (see ADR 0004): the
  /// presentation then shows the time controls disabled with the reason.
  final bool dueTimeSupported;
  final StreamController<WorkspaceState> _controller =
      StreamController<WorkspaceState>.broadcast();
  WorkspaceState _state;

  /// Set while a save runs. A second save or a create is refused meanwhile.
  bool _saving = false;

  /// Set while a gate resolution or a create commit runs. Edits, navigation,
  /// saves, creates and a second resolution are refused meanwhile, so a
  /// transition is never executed twice or interleaved.
  bool _transitioning = false;

  /// An incoming refresh arrived while a save or transition ran. It runs when
  /// that operation ends, so incoming data is never dropped or applied midway.
  bool _refreshQueued = false;

  /// Emits the new state after every change.
  Stream<WorkspaceState> get states => _controller.stream;

  WorkspaceState get state => _state;

  void dispose() {
    _controller.close();
  }

  // ---------------------------------------------------------------- loading

  Future<void> load() async {
    _publish(_state.copyWith(loading: true, clearError: true));
    try {
      final projects = await repository.loadProjects();
      final tasks = await repository.loadTasks();
      _publish(
        _state.copyWith(
          projects: projects,
          tasks: {for (final task in tasks) task.id: task},
          loading: false,
          clearSelectedTask: true,
          clearDraft: true,
          clearPending: true,
        ),
      );
    } on RepositoryException {
      _publish(
        _state.copyWith(
          projects: const [],
          tasks: const {},
          loading: false,
          error: WorkspaceError.loadFailed,
          clearSelectedTask: true,
          clearDraft: true,
          clearPending: true,
        ),
      );
    }
  }

  /// Creates a project the user asked for. Needs a repository that can store
  /// projects ([ProjectStore]); nothing creates a project automatically.
  Future<Result<Project, WorkspaceError>> createProject(String name) async {
    final store = repository;
    if (store is! ProjectStore) {
      return const Err(WorkspaceError.saveFailed);
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return const Err(WorkspaceError.titleRequired);
    }
    if (trimmed.length > maxTitleLength) {
      return const Err(WorkspaceError.titleTooLong);
    }
    final next = _state.projects.isEmpty
        ? 0
        : _state.projects
                  .map((p) => p.position)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final project = Project(id: ids.nextId(), name: trimmed, position: next);
    try {
      await (store as ProjectStore).saveProject(project);
    } on RepositoryException {
      return const Err(WorkspaceError.saveFailed);
    }
    _publish(_state.copyWith(projects: [..._state.projects, project]));
    return Ok(project);
  }

  /// Re-reads projects and tasks after a synchronization changed storage and
  /// publishes them, so lists, counts, the Dashboard and the selected task
  /// follow without any navigation.
  ///
  /// Returns true when the incoming data was applied now. It returns false when
  /// a save or decision is running (the refresh is queued and runs afterwards)
  /// or when storage could not be read (nothing changes).
  ///
  /// The selection is kept unless its task no longer exists. The draft is
  /// never replaced by incoming data while it holds unsaved edits:
  /// * a clean draft simply follows the stored task;
  /// * a dirty draft keeps every edited field and takes incoming values only
  ///   for fields the user did not touch; [WorkspaceState.incoming] tells the
  ///   user, and Revert loads the incoming version;
  /// * if the task was deleted incoming, a clean draft is closed, and a dirty
  ///   one is kept (Save refused) until the user discards it.
  Future<bool> refresh() async {
    if (_saving || _transitioning) {
      _refreshQueued = true;
      return false;
    }
    final List<Project> projects;
    final List<Task> tasks;
    try {
      projects = await repository.loadProjects();
      tasks = await repository.loadTasks();
    } on RepositoryException {
      return false;
    }
    if (_saving || _transitioning) {
      _refreshQueued = true;
      return false;
    }
    _publish(_applyIncoming(projects, {for (final t in tasks) t.id: t}));
    return true;
  }

  WorkspaceState _applyIncoming(
    List<Project> projects,
    Map<String, Task> tasks,
  ) {
    final selectedId = _state.selectedTaskId;
    final draft = _state.draft;
    final selection = _state.selection;
    final next = _state.copyWith(
      projects: projects,
      tasks: tasks,
      expandedTaskIds: {
        for (final id in _state.expandedTaskIds)
          if (tasks.containsKey(id)) id,
      },
      selection:
          selection is ProjectSelection &&
              !projects.any((p) => p.id == selection.projectId)
          ? const SmartViewSelection(SmartView.all)
          : selection,
    );
    if (selectedId == null || draft == null) {
      return next;
    }
    final stored = tasks[selectedId];
    if (stored == null) {
      return draft.isDirty
          ? next.copyWith(incoming: const IncomingNotice(IncomingKind.deleted))
          : next.copyWith(
              clearSelectedTask: true,
              clearDraft: true,
              clearIncoming: true,
            );
    }
    if (_sameContent(draft.base, stored)) {
      return next;
    }
    if (!draft.isDirty) {
      return next.copyWith(
        draft: EditDraft.fromTask(stored),
        clearIncoming: true,
      );
    }
    final merge = draft.mergeIncoming(stored);
    return next.copyWith(
      draft: merge.draft,
      incoming: IncomingNotice(IncomingKind.updated, merge.overlap),
    );
  }

  bool _sameContent(Task a, Task b) {
    return a.projectId == b.projectId &&
        a.parentId == b.parentId &&
        a.title == b.title &&
        a.status == b.status &&
        a.priority == b.priority &&
        a.dueDate == b.dueDate &&
        a.dueTime == b.dueTime &&
        a.notes == b.notes &&
        a.position == b.position;
  }

  /// Runs a refresh that arrived while a save or transition was running.
  void _drainQueuedRefresh() {
    if (_refreshQueued && !_saving && !_transitioning) {
      _refreshQueued = false;
      unawaited(refresh());
    }
  }

  // ------------------------------------------------- navigation and visibility

  void requestSelectView(SmartView view) {
    _request(TransitionSelectView(view));
  }

  void requestSelectProject(String projectId) {
    _request(TransitionSelectProject(projectId));
  }

  void requestSelectDashboard() {
    _request(const TransitionSelectDashboard());
  }

  /// Selects [taskId], or clears the selection when it is null. An unknown id
  /// is ignored.
  void requestSelectTask(String? taskId) {
    if (taskId != null && !_state.tasks.containsKey(taskId)) {
      return;
    }
    _request(TransitionSelectTask(taskId));
  }

  void requestSearch(String query) {
    _request(TransitionSearch(query));
  }

  /// Sorting never hides a task, so it is never gated.
  void requestSort(TaskSort sort) {
    _publish(_state.copyWith(sort: sort));
  }

  /// Filters the list by status (null shows all). Like sort it is never gated
  /// and never touches the draft. A selected task the filter hides stays
  /// selected; the existing "hidden in this view" notice shows.
  void requestStatusFilter(TaskStatus? status) {
    _publish(
      _state.copyWith(statusFilter: status, clearStatusFilter: status == null),
    );
  }

  /// Collapsing a parent may hide the selected row. The selection is kept.
  void toggleExpanded(String taskId) {
    final expanded = {..._state.expandedTaskIds};
    if (!expanded.remove(taskId)) {
      expanded.add(taskId);
    }
    _publish(_state.copyWith(expandedTaskIds: expanded));
  }

  // ----------------------------------------------------------------- creation

  /// Creates a root task in [projectId] and selects it.
  ///
  /// Validation errors return immediately without touching state. With a
  /// dirty draft, the creation waits in the gate and nothing is persisted yet.
  Future<Result<Task, WorkspaceError>> requestCreateRootTask({
    required String title,
    required String projectId,
  }) async {
    if (_state.pending != null) {
      return const Err<Task, WorkspaceError>(
        WorkspaceError.unsavedChangesPending,
      );
    }
    if (_saving || _transitioning) {
      return const Err<Task, WorkspaceError>(
        WorkspaceError.operationInProgress,
      );
    }
    final projects = {
      for (final project in _state.projects) project.id: project,
    };
    final created = createRootTask(
      title: title,
      projectId: projectId,
      projects: projects,
      tasks: _state.tasks.values,
      ids: ids,
    );
    switch (created) {
      case Ok(:final value):
        return _proposeCreate(value, expandParentId: null);
      case Err(:final error):
        return Err<Task, WorkspaceError>(_createCode(error));
    }
  }

  /// Creates a subtask under [parentId], expands the parent and selects the
  /// new child. The parent's status is never changed.
  Future<Result<Task, WorkspaceError>> requestCreateSubtask({
    required String title,
    required String parentId,
  }) async {
    if (_state.pending != null) {
      return const Err<Task, WorkspaceError>(
        WorkspaceError.unsavedChangesPending,
      );
    }
    if (_saving || _transitioning) {
      return const Err<Task, WorkspaceError>(
        WorkspaceError.operationInProgress,
      );
    }
    final created = createSubtask(
      title: title,
      parentId: parentId,
      tasks: _state.tasks.values,
      ids: ids,
    );
    switch (created) {
      case Ok(:final value):
        return _proposeCreate(value, expandParentId: parentId);
      case Err(:final error):
        return Err<Task, WorkspaceError>(_createCode(error));
    }
  }

  // ------------------------------------------------------------ draft editing

  void editDraft({
    String? title,
    TaskStatus? status,
    TaskPriority? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    DueTime? dueTime,
    bool clearDueTime = false,
    String? notes,
  }) {
    if (_transitioning) {
      return;
    }
    final draft = _state.draft;
    if (draft == null) {
      return;
    }
    // A synchronized workspace cannot store a time yet: never accept one.
    final acceptedTime = dueTimeSupported ? dueTime : null;
    _publish(
      _state.copyWith(
        draft: draft.copyWith(
          title: title,
          status: status,
          priority: priority,
          dueDate: dueDate,
          clearDueDate: clearDueDate,
          dueTime: acceptedTime,
          clearDueTime: clearDueTime,
          notes: notes,
        ),
        clearError: true,
      ),
    );
  }

  /// Returns the draft to the saved values. Never gated.
  void revertDraft() {
    // Refused while a save or transition runs. Otherwise the draft would be reset
    // to the old base while the save is in flight, and the rebase would keep the
    // reset values against the saved base.
    if (_saving || _transitioning) {
      return;
    }
    final draft = _state.draft;
    if (draft == null) {
      return;
    }
    if (_state.incoming?.kind == IncomingKind.deleted) {
      // The saved version no longer exists: reverting means leaving the task.
      _publish(
        _state.copyWith(
          clearSelectedTask: true,
          clearDraft: true,
          clearError: true,
        ),
      );
      return;
    }
    _publish(
      _state.copyWith(
        draft: EditDraft.fromTask(draft.base),
        clearIncoming: true,
        clearError: true,
      ),
    );
  }

  /// Validates and persists the draft. On failure the draft is kept as is.
  Future<Result<void, WorkspaceError>> saveDraft() async {
    if (_saving || _transitioning) {
      return const Err<void, WorkspaceError>(
        WorkspaceError.operationInProgress,
      );
    }
    _saving = true;
    try {
      return await _saveDraftUnsafe();
    } finally {
      _saving = false;
      _drainQueuedRefresh();
    }
  }

  /// The save itself. Callers hold the guard: [saveDraft], or [resolvePending]
  /// during the save step of a transition.
  Future<Result<void, WorkspaceError>> _saveDraftUnsafe() async {
    final draft = _state.draft;
    if (draft == null || !draft.isDirty) {
      return const Ok<void, WorkspaceError>(null);
    }
    if (_state.incoming?.kind == IncomingKind.deleted) {
      // Saving would resurrect a record another device deleted.
      _publish(_state.copyWith(error: WorkspaceError.taskDeletedElsewhere));
      return const Err<void, WorkspaceError>(
        WorkspaceError.taskDeletedElsewhere,
      );
    }
    switch (validateTitle(draft.title)) {
      case Err(:final error):
        final code = _titleCode(error);
        _publish(_state.copyWith(error: code));
        return Err<void, WorkspaceError>(code);
      case Ok(:final value):
        final task = draft.copyWith(title: value).toTask();
        return _persistDraft(draft, task);
    }
  }

  // ------------------------------------------------------- gate and app exit

  /// Answers the open unsaved-change decision.
  ///
  /// `save` persists the draft first. A failed save leaves the gate open.
  /// `discard` applies the transition and drops the draft. `cancel` only
  /// closes the decision.
  Future<void> resolvePending(PendingResolution resolution) async {
    final pending = _state.pending;
    if (pending == null || _saving || _transitioning) {
      return;
    }
    if (resolution == PendingResolution.cancel) {
      // Cancel restores the editing context. The draft and selection are kept.
      _publish(_state.copyWith(clearPending: true, clearError: true));
      return;
    }
    _transitioning = true;
    try {
      if (resolution == PendingResolution.save) {
        final saved = await _saveDraftUnsafe();
        if (saved is Err<void, WorkspaceError>) {
          return;
        }
        if (!identical(_state.pending, pending)) {
          return;
        }
      }
      // Discard and save commit the transition only when it succeeds. A failed
      // create keeps the draft, the selection and the pending transition.
      await _completeTransition(pending.transition);
    } finally {
      _transitioning = false;
      _drainQueuedRefresh();
    }
  }

  /// Returns true when the app may exit now. Returns false and opens the gate
  /// when there is a dirty draft.
  Future<bool> requestExit() async {
    if (_transitioning || _state.pending != null) {
      return false;
    }
    if (!_isDirty) {
      return true;
    }
    _publish(
      _state.copyWith(
        pending: const PendingTransition(TransitionExit()),
        clearError: true,
      ),
    );
    return false;
  }

  // ----------------------------------------------------------------- delete

  /// Ids of [taskId] and all its descendants (empty for an unknown task).
  List<String> subtreeOf(String taskId) =>
      leafFirstDeletionOrder(_state.tasks, [taskId]);

  /// Deletes [taskId] with its subtree in one repository transaction.
  ///
  /// Refused while a save, create or gate decision runs, or while the gate is
  /// open. A failure changes nothing. Deleting the selected task (or an
  /// ancestor of it) drops the selection and its draft: the confirm dialog has
  /// already told the user it cannot be undone.
  Future<Result<List<String>, WorkspaceError>> deleteTask(String taskId) async {
    final busy = _deleteBlocked();
    if (busy != null) {
      return Err(busy);
    }
    final store = repository;
    if (store is! TreeDeleter || !_state.tasks.containsKey(taskId)) {
      return const Err(WorkspaceError.deleteFailed);
    }
    final doomed = subtreeOf(taskId);
    _transitioning = true;
    try {
      await (store as TreeDeleter).softDeleteTaskTree(taskId);
    } on RepositoryException {
      return const Err(WorkspaceError.deleteFailed);
    } finally {
      _transitioning = false;
      _drainQueuedRefresh();
    }
    final gone = doomed.toSet();
    final tasks = {..._state.tasks}..removeWhere((id, _) => gone.contains(id));
    final selected = _state.selectedTaskId;
    final dropSelection = selected != null && gone.contains(selected);
    _publish(
      _state.copyWith(
        tasks: tasks,
        expandedTaskIds: {..._state.expandedTaskIds}..removeAll(gone),
        clearSelectedTask: dropSelection,
        clearDraft: dropSelection,
        clearError: true,
      ),
    );
    return Ok(doomed);
  }

  /// Deletes [projectId] with all its tasks. The last project cannot be
  /// deleted. Unsaved edits of a task in the project are not discarded
  /// silently: the delete is refused until they are saved or reverted.
  Future<Result<List<String>, WorkspaceError>> deleteProject(
    String projectId,
  ) async {
    final busy = _deleteBlocked();
    if (busy != null) {
      return Err(busy);
    }
    if (_state.projects.length <= 1) {
      return const Err(WorkspaceError.lastProject);
    }
    final store = repository;
    if (store is! TreeDeleter ||
        !_state.projects.any((p) => p.id == projectId)) {
      return const Err(WorkspaceError.deleteFailed);
    }
    final doomed = projectDeletionOrder(_state.tasks, projectId);
    final draft = _state.draft;
    if (draft != null && draft.isDirty && doomed.contains(draft.taskId)) {
      return const Err(WorkspaceError.unsavedChangesPending);
    }
    _transitioning = true;
    try {
      await (store as TreeDeleter).softDeleteProjectTree(projectId);
    } on RepositoryException {
      return const Err(WorkspaceError.deleteFailed);
    } finally {
      _transitioning = false;
      _drainQueuedRefresh();
    }
    final gone = doomed.toSet();
    final tasks = {..._state.tasks}..removeWhere((id, _) => gone.contains(id));
    final projects = [
      for (final p in _state.projects)
        if (p.id != projectId) p,
    ];
    final selected = _state.selectedTaskId;
    final dropSelection = selected != null && gone.contains(selected);
    final selection = _state.selection;
    _publish(
      _state.copyWith(
        projects: projects,
        tasks: tasks,
        expandedTaskIds: {..._state.expandedTaskIds}..removeAll(gone),
        selection:
            selection is ProjectSelection && selection.projectId == projectId
            ? ProjectSelection(projects.first.id)
            : selection,
        clearSelectedTask: dropSelection,
        clearDraft: dropSelection,
        clearError: true,
      ),
    );
    return Ok(doomed);
  }

  WorkspaceError? _deleteBlocked() {
    if (_state.pending != null) {
      return WorkspaceError.unsavedChangesPending;
    }
    if (_saving || _transitioning) {
      return WorkspaceError.operationInProgress;
    }
    return null;
  }

  /// Returns true when the account may be left now (sign-out). Returns false
  /// and opens the gate when there is a dirty draft; [WorkspaceState.signOutReady]
  /// is set once the user has saved or discarded.
  Future<bool> requestSignOut() async {
    if (_transitioning || _state.pending != null) {
      return false;
    }
    if (!_isDirty) {
      return true;
    }
    _publish(
      _state.copyWith(
        pending: const PendingTransition(TransitionSignOut()),
        clearError: true,
      ),
    );
    return false;
  }

  /// Clears [WorkspaceState.signOutReady] after the sign-out was carried out.
  void clearSignOutReady() {
    _publish(_state.copyWith(signOutReady: false));
  }

  // ------------------------------------------------------- internal: gate

  bool get _isDirty => _state.draft?.isDirty ?? false;

  void _request(WorkspaceTransition transition) {
    if (_state.pending != null || _transitioning) {
      // The gate is modal: navigation waits until the decision is made.
      return;
    }
    if (_isGated(transition)) {
      _publish(
        _state.copyWith(
          pending: PendingTransition(transition),
          clearError: true,
        ),
      );
      return;
    }
    _apply(transition);
  }

  /// Gated when a dirty draft would be left or hidden by [transition].
  bool _isGated(WorkspaceTransition transition) {
    final draft = _state.draft;
    if (draft == null || !draft.isDirty) {
      return false;
    }
    return switch (transition) {
      TransitionSelectTask(:final taskId) => taskId != draft.taskId,
      TransitionSelectView(:final view) => !_stillVisible(
        draft.taskId,
        SmartViewSelection(view),
        _state.searchQuery,
      ),
      TransitionSelectProject(:final projectId) => !_stillVisible(
        draft.taskId,
        ProjectSelection(projectId),
        _state.searchQuery,
      ),
      TransitionSelectDashboard() => true,
      TransitionSearch(:final query) => !_stillVisible(
        draft.taskId,
        _state.selection,
        query,
      ),
      TransitionCreate() || TransitionExit() || TransitionSignOut() => true,
    };
  }

  bool _stillVisible(String taskId, NavSelection selection, String query) {
    final task = _state.tasks[taskId];
    return task != null && matchesFilter(task, selection, query, _state.today);
  }

  /// Applies a navigation transition that is not gated (or was accepted).
  void _apply(WorkspaceTransition transition) {
    switch (transition) {
      case TransitionSelectView(:final view):
        _publish(_withFilter(selection: SmartViewSelection(view)));
      case TransitionSelectProject(:final projectId):
        _publish(_withFilter(selection: ProjectSelection(projectId)));
      case TransitionSelectDashboard():
        _publish(_withFilter(selection: const DashboardSelection()));
      case TransitionSelectTask(:final taskId):
        _publish(_selectingTask(taskId));
      case TransitionSearch(:final query):
        _publish(_withFilter(query: query));
      case TransitionExit():
        _publish(
          _state.copyWith(
            clearPending: true,
            clearDraft: true,
            exitReady: true,
          ),
        );
      case TransitionSignOut():
        _publish(
          _state.copyWith(
            clearPending: true,
            clearDraft: true,
            clearSelectedTask: true,
            signOutReady: true,
          ),
        );
      case TransitionCreate():
        throw StateError('Creation is committed by _commitCreate, not _apply');
    }
  }

  /// Applies the transition held in the gate, after the user's decision.
  Future<void> _completeTransition(WorkspaceTransition transition) async {
    switch (transition) {
      case TransitionCreate(:final candidate, :final expandParentId):
        final committed = await _commitCreate(
          candidate,
          expandParentId: expandParentId,
        );
        if (committed case Err<Task, WorkspaceError>(:final error)) {
          _publish(_state.copyWith(error: error));
        }
      case _:
        _apply(transition);
    }
  }

  /// Changes the selection or search. The selection survives only when the
  /// selected task still matches the new filter; otherwise it clears.
  WorkspaceState _withFilter({NavSelection? selection, String? query}) {
    final nextSelection = selection ?? _state.selection;
    final nextQuery = query ?? _state.searchQuery;
    final selectedId = _state.selectedTaskId;
    final keep =
        selectedId != null &&
        _stillVisible(selectedId, nextSelection, nextQuery);
    return _state.copyWith(
      selection: nextSelection,
      searchQuery: nextQuery,
      clearPending: true,
      clearError: true,
      clearSelectedTask: !keep,
      clearDraft: !keep,
    );
  }

  WorkspaceState _selectingTask(String? taskId) {
    if (taskId == _state.selectedTaskId) {
      return _state.copyWith(clearPending: true, clearError: true);
    }
    if (taskId == null) {
      return _state.copyWith(
        clearSelectedTask: true,
        clearDraft: true,
        clearPending: true,
        clearError: true,
      );
    }
    final task = _state.tasks[taskId];
    if (task == null) {
      return _state.copyWith(clearPending: true);
    }
    return _state.copyWith(
      selectedTaskId: taskId,
      draft: EditDraft.fromTask(task),
      clearPending: true,
      clearError: true,
    );
  }

  // ------------------------------------------------------- internal: persist

  Future<Result<Task, WorkspaceError>> _proposeCreate(
    Task candidate, {
    required String? expandParentId,
  }) async {
    if (_isDirty) {
      _publish(
        _state.copyWith(
          pending: PendingTransition(
            TransitionCreate(candidate, expandParentId: expandParentId),
          ),
          clearError: true,
        ),
      );
      return Ok<Task, WorkspaceError>(candidate);
    }
    _transitioning = true;
    try {
      return await _commitCreate(candidate, expandParentId: expandParentId);
    } finally {
      _transitioning = false;
      _drainQueuedRefresh();
    }
  }

  /// Persists [candidate] and selects it. On failure nothing changes; the
  /// caller decides whether to report the error.
  Future<Result<Task, WorkspaceError>> _commitCreate(
    Task candidate, {
    required String? expandParentId,
  }) async {
    // Re-check the parent against the state as it is now. A save that ran
    // while the gate was open may have archived it.
    final parentId = candidate.parentId;
    if (parentId != null) {
      final parent = _state.tasks[parentId];
      if (parent == null) {
        return const Err<Task, WorkspaceError>(WorkspaceError.unknownParent);
      }
      if (parent.status == TaskStatus.archived) {
        return const Err<Task, WorkspaceError>(WorkspaceError.parentArchived);
      }
    }
    try {
      await repository.saveTask(candidate);
    } on RepositoryException {
      return const Err<Task, WorkspaceError>(WorkspaceError.saveFailed);
    }
    final tasks = {..._state.tasks, candidate.id: candidate};
    final expanded = expandParentId == null
        ? _state.expandedTaskIds
        : {..._state.expandedTaskIds, expandParentId};
    _publish(
      _revealing(
        _state.copyWith(
          tasks: tasks,
          expandedTaskIds: expanded,
          selectedTaskId: candidate.id,
          draft: EditDraft.fromTask(candidate),
          clearPending: true,
          clearError: true,
        ),
        candidate,
      ),
    );
    return Ok<Task, WorkspaceError>(candidate);
  }

  /// Makes a newly created task visible. An undated task is hidden in the
  /// smart views, so the selection moves to its project. A search that hides
  /// it is cleared. The task never receives a due date, and the selection is
  /// never dropped.
  WorkspaceState _revealing(WorkspaceState next, Task candidate) {
    final selection = inSelection(candidate, next.selection, next.today)
        ? next.selection
        : ProjectSelection(candidate.projectId);
    final query = matchesSearch(candidate, next.searchQuery)
        ? next.searchQuery
        : '';
    // A filter that would hide the new task is cleared as well.
    final filter = next.statusFilter;
    final clearFilter = filter != null && candidate.status != filter;
    return next.copyWith(
      selection: selection,
      searchQuery: query,
      clearStatusFilter: clearFilter,
    );
  }

  Future<Result<void, WorkspaceError>> _persistDraft(
    EditDraft snapshot,
    Task task,
  ) async {
    try {
      await repository.saveTask(task);
    } on RepositoryException {
      _publish(_state.copyWith(error: WorkspaceError.saveFailed));
      return const Err<void, WorkspaceError>(WorkspaceError.saveFailed);
    }
    final tasks = {..._state.tasks, task.id: task};
    final current = _state.draft;
    // Edits typed while the save was in flight must survive the rebase.
    final draftAfter = (current != null && current.taskId == snapshot.taskId)
        ? current.rebaseAfterSave(snapshot: snapshot, savedTask: task)
        : current;
    _publish(
      _state.copyWith(
        tasks: tasks,
        draft: draftAfter,
        clearIncoming: true,
        clearError: true,
      ),
    );
    return const Ok<void, WorkspaceError>(null);
  }

  void _publish(WorkspaceState next) {
    // The incoming notice belongs to one task's draft: it ends with it.
    final stale =
        next.incoming != null &&
        (next.draft == null || next.selectedTaskId != _state.selectedTaskId);
    _state = (stale ? next.copyWith(clearIncoming: true) : next).copyWith(
      today: clock.today(),
    );
    _controller.add(_state);
  }

  WorkspaceError _titleCode(TitleError error) {
    return switch (error) {
      TitleError.required => WorkspaceError.titleRequired,
      TitleError.tooLong => WorkspaceError.titleTooLong,
    };
  }

  WorkspaceError _createCode(CreateError error) {
    return switch (error) {
      CreateError.titleRequired => WorkspaceError.titleRequired,
      CreateError.titleTooLong => WorkspaceError.titleTooLong,
      CreateError.unknownProject => WorkspaceError.unknownProject,
      CreateError.unknownParent => WorkspaceError.unknownParent,
      CreateError.parentArchived => WorkspaceError.parentArchived,
      CreateError.idCollision => WorkspaceError.saveFailed,
    };
  }
}
