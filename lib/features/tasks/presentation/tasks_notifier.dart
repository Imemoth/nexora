import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Thin presentation adapter over [TaskWorkspace].
///
/// Forwards intents unchanged and notifies listeners on every workspace
/// emission. It holds no business state and no rules.
final class TasksNotifier extends ChangeNotifier {
  TasksNotifier(this._workspace) {
    _subscription = _workspace.states.listen((_) => notifyListeners());
  }

  final TaskWorkspace _workspace;
  late final StreamSubscription<WorkspaceState> _subscription;

  WorkspaceState get state => _workspace.state;

  /// Whether a due date may carry a time in this workspace (ADR 0004).
  bool get dueTimeSupported => _workspace.dueTimeSupported;

  void selectView(SmartView view) => _workspace.requestSelectView(view);

  void selectProject(String projectId) =>
      _workspace.requestSelectProject(projectId);

  void selectDashboard() => _workspace.requestSelectDashboard();

  Future<Result<Project, WorkspaceError>> createProject(String name) =>
      _workspace.createProject(name);

  void selectTask(String? taskId) => _workspace.requestSelectTask(taskId);

  /// Brings [taskId] into view and selects it (used when the user clicks a
  /// reminder notification): clears the search, opens the task's project,
  /// expands its ancestors. With unsaved edits only the selection is requested,
  /// so the usual unsaved-change gate decides.
  void revealTask(String taskId) {
    final task = state.tasks[taskId];
    if (task == null) {
      return;
    }
    if (state.draft?.isDirty ?? false) {
      _workspace.requestSelectTask(taskId);
      return;
    }
    _workspace.requestSearch('');
    _workspace.requestSelectProject(task.projectId);
    var parent = task.parentId;
    while (parent != null) {
      if (!state.expandedTaskIds.contains(parent)) {
        _workspace.toggleExpanded(parent);
      }
      parent = state.tasks[parent]?.parentId;
    }
    _workspace.requestSelectTask(taskId);
  }

  /// Opens a related subtask (a row of the details panel): expands every
  /// collapsed ancestor so it can appear in the tree, then selects it.
  ///
  /// Nothing the user chose is undone: the search, the status filter, the view
  /// and any unsaved draft stay as they are. Selection goes through the
  /// unsaved-change gate like any other. When the current search, filter or view
  /// cannot show the task, the list says so and offers one explicit action for
  /// each cause (`WorkspaceState.hiddenReasons`).
  void revealSubtask(String taskId) {
    expandAncestorsOf(taskId);
    _workspace.requestSelectTask(taskId);
  }

  /// Expands every collapsed ancestor of [taskId] (never the task itself).
  /// Expansion is a view matter: it does not touch the draft and is never gated.
  void expandAncestorsOf(String taskId) {
    var parent = state.tasks[taskId]?.parentId;
    final seen = <String>{};
    while (parent != null && seen.add(parent)) {
      if (!state.expandedTaskIds.contains(parent)) {
        _workspace.toggleExpanded(parent);
      }
      parent = state.tasks[parent]?.parentId;
    }
  }

  void search(String query) => _workspace.requestSearch(query);

  void sort(TaskSort sort) => _workspace.requestSort(sort);

  void filterStatus(TaskStatus? status) =>
      _workspace.requestStatusFilter(status);

  void toggleExpanded(String taskId) => _workspace.toggleExpanded(taskId);

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
    _workspace.editDraft(
      title: title,
      status: status,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
      dueTime: dueTime,
      clearDueTime: clearDueTime,
      notes: notes,
    );
  }

  void revertDraft() => _workspace.revertDraft();

  Future<Result<void, WorkspaceError>> saveDraft() => _workspace.saveDraft();

  Future<Result<Task, WorkspaceError>> createRootTask({
    required String title,
    required String projectId,
  }) => _workspace.requestCreateRootTask(title: title, projectId: projectId);

  Future<Result<Task, WorkspaceError>> createSubtask({
    required String title,
    required String parentId,
  }) => _workspace.requestCreateSubtask(title: title, parentId: parentId);

  Future<void> resolvePending(PendingResolution resolution) =>
      _workspace.resolvePending(resolution);

  Future<bool> requestExit() => _workspace.requestExit();

  /// Number of subtasks under [taskId], for the confirm dialog.
  int subtaskCountOf(String taskId) => _workspace.subtreeOf(taskId).length - 1;

  int taskCountInProject(String projectId) => _workspace.state.tasks.values
      .where((task) => task.projectId == projectId)
      .length;

  Future<Result<List<String>, WorkspaceError>> deleteTask(String taskId) =>
      _workspace.deleteTask(taskId);

  Future<Result<List<String>, WorkspaceError>> deleteProject(
    String projectId,
  ) => _workspace.deleteProject(projectId);

  Future<void> Function()? _signOutAction;

  /// Signs out through the unsaved-change gate: at once when nothing is
  /// unsaved, otherwise after the user has saved or discarded.
  Future<void> requestSignOut(Future<void> Function() action) async {
    final allowed = await _workspace.requestSignOut();
    if (allowed) {
      await action();
    } else {
      _signOutAction = action;
    }
  }

  /// Runs the sign-out the gate was holding, once the user allowed it.
  Future<void> completeSignOut() async {
    final action = _signOutAction;
    _signOutAction = null;
    _workspace.clearSignOutReady();
    if (action != null) {
      await action();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
