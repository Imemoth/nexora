import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';

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

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
