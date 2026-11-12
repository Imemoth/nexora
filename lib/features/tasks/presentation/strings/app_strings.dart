import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Every user-visible string in Phase 1. English, centralized for later
/// localization. Widgets must not contain visible-text literals.
abstract final class AppStrings {
  static const appName = 'Nexora';
  static const projectsHeader = 'Projects';
  static const selectTaskPrompt = 'Select a task';
  static const noTasksHere = 'No tasks here yet';
  static const emptyProject = 'No tasks in this project yet';
  static const noSearchMatches = 'No tasks match your search';
  static const clearSearch = 'Clear';
  static const searchHint = 'Search title and notes';
  static const selectedTaskHidden = 'Selected task is hidden in this view';
  static const readyForReview = 'Ready for review';
  static const sortTooltip = 'Sort';
  static const expandTask = 'Expand';
  static const collapseTask = 'Collapse';
  static const fieldStatus = 'Status';
  static const fieldPriority = 'Priority';
  static const fieldDue = 'Due';
  static const fieldNotes = 'Notes';
  static const noDueDate = 'No due date';
  static const noNotes = 'No notes';
  static const fieldTitle = 'Title';
  static const fieldProject = 'Project';
  static const fieldParent = 'Parent';
  static const unsavedIndicator = 'Edited, not saved';
  static const saveAction = 'Save';
  static const revertAction = 'Revert';
  static const addSubtaskAction = 'Add subtask';
  static const clearDueDate = 'Clear due date';
  static const closeDetails = 'Close details';
  static const pickDueDate = 'Pick date';
  static const newTaskAction = 'New task';
  static const createAction = 'Create';
  static const cancelAction = 'Cancel';
  static const discardAction = 'Discard';
  static const newTaskTitle = 'New task';
  static const newSubtaskTitle = 'New subtask';
  static const taskCreated = 'Task created';
  static const unsavedChangesTitle = 'Unsaved changes';
  static const unsavedChangesBody =
      'Save or discard your changes, or cancel to keep editing.';
  static const titleRequired = 'Enter a title.';
  static const titleTooLong = 'Use 200 characters or fewer.';
  static const errorUnknownProject = 'That project no longer exists.';
  static const errorUnknownParent = 'That task no longer exists.';
  static const errorParentArchived = 'An archived task cannot get subtasks.';
  static const errorSaveFailed = 'Could not save. Your changes are kept.';
  static const errorLoadFailed = 'Could not load tasks.';
  static const errorOperationInProgress =
      'Please wait for the current change to finish.';
  static const errorGatePending = 'Save, discard or cancel your changes first.';
  static const errorDatabaseOpen =
      'Nexora could not open its local database. Close any other copy of Nexora and start it again. Your data has not been changed.';
  static const defaultProjectName = 'Inbox';
  static const syncNowAction = 'Sync now';
  static const syncDisabled = 'Synchronization is off';
  static const syncing = 'Synchronizing…';
  static const syncRetrying = 'Offline or server unavailable. Retrying; nothing is lost';
  static const syncSignInNeeded = 'Sign in to synchronize. Your changes are kept';
  static const syncDeviceRevoked = 'This device was removed. Your data stays here';
  static const syncError = 'Synchronization stopped. Your changes are kept';
  static const syncUpToDate = 'Up to date';
  static String syncConflicts(int n) =>
      n == 1 ? '1 conflict needs your decision' : '$n conflicts need your decision';
  static String syncRejected(int n) =>
      n == 1 ? '1 change was refused and is kept' : '$n changes were refused and are kept';
  static String syncPending(int n) =>
      n == 1 ? '1 change waiting to be sent' : '$n changes waiting to be sent';
  static const desktopOnlyNotice =
      'Nexora needs a window at least 900 px wide.';

  static String errorMessage(WorkspaceError error) {
    return switch (error) {
      WorkspaceError.titleRequired => titleRequired,
      WorkspaceError.titleTooLong => titleTooLong,
      WorkspaceError.unknownProject => errorUnknownProject,
      WorkspaceError.unknownParent => errorUnknownParent,
      WorkspaceError.parentArchived => errorParentArchived,
      WorkspaceError.saveFailed => errorSaveFailed,
      WorkspaceError.loadFailed => errorLoadFailed,
      WorkspaceError.unsavedChangesPending => errorGatePending,
      WorkspaceError.operationInProgress => errorOperationInProgress,
    };
  }

  static String smartViewLabel(SmartView view) {
    return switch (view) {
      SmartView.today => 'Today',
      SmartView.next7Days => 'Next 7 Days',
      SmartView.overdue => 'Overdue',
      SmartView.all => 'All',
    };
  }

  static String taskCount(int count) {
    return count == 1 ? '1 task' : '$count tasks';
  }

  static String progress(int done, int total) => '$done/$total';

  static String dueLabel(CalendarDate date) => 'Due ${date.toIsoString()}';

  static String sortLabel(TaskSort sort) {
    return switch (sort) {
      TaskSort.position => 'Position',
      TaskSort.dueDate => 'Due date',
      TaskSort.priority => 'Priority',
      TaskSort.title => 'Title',
    };
  }

  static String statusLabel(TaskStatus status) {
    return switch (status) {
      TaskStatus.open => 'Open',
      TaskStatus.inProgress => 'In progress',
      TaskStatus.review => 'Review',
      TaskStatus.done => 'Done',
      TaskStatus.archived => 'Archived',
    };
  }

  static String priorityLabel(TaskPriority priority) {
    return switch (priority) {
      TaskPriority.none => 'No priority',
      TaskPriority.low => 'Low',
      TaskPriority.medium => 'Medium',
      TaskPriority.high => 'High',
    };
  }
}
