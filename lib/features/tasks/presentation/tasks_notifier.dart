import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
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

  void selectView(SmartView view) => _workspace.requestSelectView(view);

  void selectProject(String projectId) =>
      _workspace.requestSelectProject(projectId);

  void selectTask(String? taskId) => _workspace.requestSelectTask(taskId);

  void search(String query) => _workspace.requestSearch(query);

  void sort(TaskSort sort) => _workspace.requestSort(sort);

  void toggleExpanded(String taskId) => _workspace.toggleExpanded(taskId);

  void editDraft({
    String? title,
    TaskStatus? status,
    TaskPriority? priority,
    CalendarDate? dueDate,
    bool clearDueDate = false,
    String? notes,
  }) {
    _workspace.editDraft(
      title: title,
      status: status,
      priority: priority,
      dueDate: dueDate,
      clearDueDate: clearDueDate,
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

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
