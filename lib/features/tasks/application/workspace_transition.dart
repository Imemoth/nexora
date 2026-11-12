import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';

/// A user request that the unsaved-change gate may hold.
sealed class WorkspaceTransition {
  const WorkspaceTransition();
}

final class TransitionSelectView extends WorkspaceTransition {
  const TransitionSelectView(this.view);

  final SmartView view;
}

final class TransitionSelectProject extends WorkspaceTransition {
  const TransitionSelectProject(this.projectId);

  final String projectId;
}

/// [taskId] null clears the selection.
final class TransitionSelectTask extends WorkspaceTransition {
  const TransitionSelectTask(this.taskId);

  final String? taskId;
}

final class TransitionSearch extends WorkspaceTransition {
  const TransitionSearch(this.query);

  final String query;
}

/// A validated new task that is not yet persisted. [expandParentId] is set
/// when the task is a subtask, so its parent is expanded on commit.
final class TransitionCreate extends WorkspaceTransition {
  const TransitionCreate(this.candidate, {this.expandParentId});

  final Task candidate;
  final String? expandParentId;
}

final class TransitionExit extends WorkspaceTransition {
  const TransitionExit();
}

final class PendingTransition {
  const PendingTransition(this.transition);

  final WorkspaceTransition transition;
}

/// The user's answer to the unsaved-change dialog.
enum PendingResolution { save, discard, cancel }
