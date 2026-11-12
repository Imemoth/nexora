import 'dart:async';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_creation_rules.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
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
  }) : _state = WorkspaceState.initial(clock.today());

  final TaskRepository repository;
  final Clock clock;
  final IdGenerator ids;
  final StreamController<WorkspaceState> _controller =
      StreamController<WorkspaceState>.broadcast();
  WorkspaceState _state;

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

  // ------------------------------------------------- navigation and visibility

  void requestSelectView(SmartView view) {
    _request(TransitionSelectView(view));
  }

  void requestSelectProject(String projectId) {
    _request(TransitionSelectProject(projectId));
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
    String? notes,
  }) {
    final draft = _state.draft;
    if (draft == null) {
      return;
    }
    _publish(
      _state.copyWith(
        draft: draft.copyWith(
          title: title,
          status: status,
          priority: priority,
          dueDate: dueDate,
          clearDueDate: clearDueDate,
          notes: notes,
        ),
        clearError: true,
      ),
    );
  }

  /// Returns the draft to the saved values. Never gated.
  void revertDraft() {
    final draft = _state.draft;
    if (draft == null) {
      return;
    }
    _publish(
      _state.copyWith(draft: EditDraft.fromTask(draft.base), clearError: true),
    );
  }

  /// Validates and persists the draft. On failure the draft is kept as is.
  Future<Result<void, WorkspaceError>> saveDraft() async {
    final draft = _state.draft;
    if (draft == null || !draft.isDirty) {
      return const Ok<void, WorkspaceError>(null);
    }
    switch (validateTitle(draft.title)) {
      case Err(:final error):
        final code = _titleCode(error);
        _publish(_state.copyWith(error: code));
        return Err<void, WorkspaceError>(code);
      case Ok(:final value):
        final task = draft.copyWith(title: value).toTask();
        return _persistDraft(draft.taskId, task);
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
    if (pending == null) {
      return;
    }
    switch (resolution) {
      case PendingResolution.cancel:
        _publish(_state.copyWith(clearPending: true, clearError: true));
      case PendingResolution.save:
        final saved = await saveDraft();
        if (saved is Err<void, WorkspaceError>) {
          return;
        }
        if (!identical(_state.pending, pending)) {
          return;
        }
        await _completeTransition(pending.transition);
      case PendingResolution.discard:
        await _completeTransition(pending.transition);
    }
  }

  /// Returns true when the app may exit now. Returns false and opens the gate
  /// when there is a dirty draft.
  Future<bool> requestExit() async {
    if (_state.pending != null) {
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

  // ------------------------------------------------------- internal: gate

  bool get _isDirty => _state.draft?.isDirty ?? false;

  void _request(WorkspaceTransition transition) {
    if (_state.pending != null) {
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
      TransitionSearch(:final query) => !_stillVisible(
        draft.taskId,
        _state.selection,
        query,
      ),
      TransitionCreate() || TransitionExit() => true,
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
        if (committed is Err<Task, WorkspaceError>) {
          _publish(_state.copyWith(error: WorkspaceError.saveFailed));
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
    return _commitCreate(candidate, expandParentId: expandParentId);
  }

  /// Persists [candidate] and selects it. On failure nothing changes; the
  /// caller decides whether to report the error.
  Future<Result<Task, WorkspaceError>> _commitCreate(
    Task candidate, {
    required String? expandParentId,
  }) async {
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
      _state.copyWith(
        tasks: tasks,
        expandedTaskIds: expanded,
        selectedTaskId: candidate.id,
        draft: EditDraft.fromTask(candidate),
        clearPending: true,
        clearError: true,
      ),
    );
    return Ok<Task, WorkspaceError>(candidate);
  }

  Future<Result<void, WorkspaceError>> _persistDraft(
    String taskId,
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
    final sameDraftStillShown = current != null && current.taskId == taskId;
    _publish(
      _state.copyWith(
        tasks: tasks,
        draft: sameDraftStillShown ? EditDraft.fromTask(task) : null,
        clearError: true,
      ),
    );
    return const Ok<void, WorkspaceError>(null);
  }

  void _publish(WorkspaceState next) {
    _state = next.copyWith(today: clock.today());
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
