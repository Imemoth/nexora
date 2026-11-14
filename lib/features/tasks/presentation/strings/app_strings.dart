import 'package:nexora/features/tasks/application/settings_store.dart';
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
  static const signInAction = 'Sign in';
  static const signOutAction = 'Sign out';
  static const signInTitle = 'Sign in to synchronize';
  static const emailLabel = 'Email';
  static const passwordLabel = 'Password';
  static const signInInvalid = 'Wrong email or password';
  static const signInUnconfirmed = 'Confirm your email address first';
  static const signInAnonymous = 'Anonymous accounts cannot synchronize';
  static const signInOffline = 'No connection. Your local data is unchanged';
  static const signInRateLimited = 'Too many attempts. Try again later';
  static const signInFailed = 'Sign-in failed. Try again';
  static const signInAccountStorage =
      "Signed in, but this account's data folder could not be opened on this computer. Nothing was changed. Check the disk and try again";
  static const signInTimedOut =
      'Sign-in is taking too long. Check the connection and try again';
  static const accountLocalOnly = 'Local workspace, not synchronized';
  static const accountSessionExpired =
      'Session ended. Sign in again; your data on this device is kept';
  static const accountSignedOutNotice = 'You signed out';
  static const accountStorageProblem =
      'The protected session store could not be written';
  static String accountSignedInAs(String email) => 'Signed in as $email';
  static const newProjectAction = 'New project';
  static const newProjectTitle = 'New project';
  static const projectNameLabel = 'Project name';
  static const emptyAccountTitle = 'This account has no projects yet';
  static const emptyAccountBody =
      'Create a project, or import projects and tasks from this computer. Nothing is imported automatically.';
  static const importLocalAction = 'Import local data';
  static const importTitle = 'Import local data';
  static const importIntro =
      'Choose what to copy into this account. Your local workspace is not changed. A verified backup of this account is made first.';
  static const importNothingToOffer =
      'There is nothing on this computer that can be imported.';
  static const importNewProject = 'New project';
  static const importAgainAnyway = 'Import again anyway';
  static const importAlreadyDone = 'Already imported into this account';
  static const importSameName = 'A project with this name already exists';
  static const importAction = 'Import selected';
  static const importWorking = 'Importing…';
  static const importDestinationLabel = 'Into';
  static const importFailed =
      'The import did not run and nothing was changed. Your backup and local data are intact';
  static const importBackupNote = 'Backup of this account saved at';
  static String importTaskCount(int n) => n == 1 ? '1 task' : '$n tasks';
  static String importSkippedNote(
    int localOnly,
    int unclassified,
    int deleted,
  ) =>
      'Not offered: $localOnly local-only, $unclassified of unknown origin, $deleted deleted';
  static String importDone(int projects, int tasks, int skipped) =>
      'Imported $projects project(s) and $tasks task(s); $skipped skipped as duplicates';
  static const conflictsTitle = 'Resolve conflicts';
  static const conflictsOpenTooltip = 'Review and resolve the conflicts';
  static const conflictsNoneLeft = 'All conflicts are resolved.';
  static const conflictsResolvedNote = 'Conflict resolved. Synchronizing…';
  static const conflictsListHeader = 'Waiting for your decision';
  static const conflictFieldColumn = 'Field';
  static const conflictLocalColumn = 'Your version (this device)';
  static const conflictServerColumn = 'Server version';
  static const conflictDiffers = 'Differs';
  static const conflictSideDeleted = 'Deleted';
  static const conflictSideUnavailable = 'Not recorded';
  static const conflictStatusOpen = 'Needs your decision';
  static const conflictStatusElsewhere =
      'Already decided on another device. Choose how to apply it here';
  static const conflictStatusResolving = 'Sending your decision…';
  static const conflictPickIntro =
      'To merge, choose which version to keep for each field:';
  static const conflictPickLocal = 'Mine';
  static const conflictPickServer = 'Server';
  static const conflictConfirmAction = 'Confirm';
  static const conflictCancelAction = 'Cancel';
  static const conflictCloseAction = 'Close';
  static String conflictProjectLine(String name) => 'Project: $name';
  static String conflictTitleCount(int n) =>
      n == 1 ? 'Resolve conflict' : 'Resolve conflicts ($n)';
  static String conflictKindSummary(String kind, bool isTask) {
    final what = isTask ? 'task' : 'project';
    return switch (kind) {
      'field' =>
        'This $what was changed on two devices. Choose which version to keep.',
      'exists' =>
        'This $what was created on two devices with different values. Choose which version to keep.',
      'edit_deleted' =>
        'You changed this $what, but it was deleted on another device.',
      'delete_edited' =>
        'You deleted this $what, but it was changed on another device.',
      'parent_has_live_children' =>
        'You deleted this $what, but another device added items inside it.',
      _ => 'This $what needs your decision.',
    };
  }

  static String conflictChoiceLabel(String choice, String kind) {
    switch (choice) {
      case 'useServer':
        return switch (kind) {
          'edit_deleted' => 'Accept the deletion',
          'delete_edited' ||
          'parent_has_live_children' => 'Keep the item (server version)',
          _ => 'Use server version',
        };
      case 'keepLocal':
        return switch (kind) {
          'delete_edited' ||
          'parent_has_live_children' => 'Delete it anyway (my version)',
          _ => 'Keep my version',
        };
      case 'merge':
        return 'Merge selected fields';
      default:
        return 'Keep my changes as a new copy';
    }
  }

  static String conflictChoiceHelp(String choice, String kind) {
    switch (choice) {
      case 'useServer':
        return switch (kind) {
          'edit_deleted' =>
            'The item stays deleted. Your changes are not applied.',
          'delete_edited' || 'parent_has_live_children' =>
            'The item stays. Your deletion is not applied.',
          _ =>
            'This device takes the server value. Your change is not applied.',
        };
      case 'keepLocal':
        return switch (kind) {
          'delete_edited' ||
          'parent_has_live_children' => 'The item is deleted on all devices.',
          _ => 'Your value replaces the server value on all devices.',
        };
      case 'merge':
        return 'Keep the version you pick for each field, on all devices.';
      default:
        return 'The deleted item stays deleted. Your changes are saved as a new item.';
    }
  }

  static String conflictConfirmTitle(String choice) => switch (choice) {
    'useServer' => 'Use the server version?',
    'keepLocal' => 'Keep your version?',
    _ => 'Apply the merged fields?',
  };

  static String conflictConfirmBody(String choice, String kind) {
    switch (choice) {
      case 'useServer':
        return switch (kind) {
          'edit_deleted' =>
            'Your changes to this item will be discarded and it stays deleted.',
          'delete_edited' || 'parent_has_live_children' =>
            'Your deletion will be discarded and the item stays.',
          _ => 'Your version of the conflicting fields will be discarded on this device.',
        };
      case 'keepLocal':
        return switch (kind) {
          'delete_edited' || 'parent_has_live_children' =>
            'The item will be deleted on all your devices.',
          _ => 'The server version of the conflicting fields will be overwritten on all your devices.',
        };
      default:
        return 'The versions you did not pick will be discarded on all your devices.';
    }
  }

  static const conflictOffline =
      'No connection. Nothing was changed: your change and the conflict are still here. Try again when you are online.';
  static const conflictAuth =
      'Sign in again to resolve this conflict. Nothing was changed.';
  static const conflictRevoked =
      'This device was removed from the account. Nothing was changed.';
  static const conflictElsewhere =
      'Another device already decided this conflict. Updating this device…';
  static const conflictUnsupported =
      'That choice is not available for this conflict. Nothing was changed.';
  static const conflictBusy =
      'A decision for this conflict is already being sent.';
  static const conflictGone =
      'This conflict is no longer waiting for a decision.';
  static const conflictFailed =
      'Something went wrong. Nothing was changed. Try again.';
  static String conflictRejected(String? code) =>
      'The server refused this decision${code == null ? '' : ' ($code)'}. Nothing was changed.';
  static const syncNowAction = 'Sync now';
  static const syncDisabled = 'Synchronization is off';
  static const syncing = 'Synchronizing…';
  static const syncRetrying =
      'Offline or server unavailable. Retrying; nothing is lost';
  static const syncSignInNeeded =
      'Sign in to synchronize. Your changes are kept';
  static const syncDeviceRevoked =
      'This device was removed. Your data stays here';
  static const syncError = 'Synchronization stopped. Your changes are kept';
  static const syncUpToDate = 'Up to date';
  static String syncConflicts(int n) => n == 1
      ? '1 conflict needs your decision'
      : '$n conflicts need your decision';
  static String syncRejected(int n) => n == 1
      ? '1 change was refused and is kept'
      : '$n changes were refused and are kept';
  static String syncPending(int n) =>
      n == 1 ? '1 change waiting to be sent' : '$n changes waiting to be sent';
  static const desktopOnlyNotice =
      'Nexora needs a window at least 900 px wide.';

  static const deleteAction = 'Delete';
  static const deleteTaskAction = 'Delete task';
  static const deleteProjectAction = 'Delete project';
  static const deleteTaskTitle = 'Delete task?';
  static const deleteProjectTitle = 'Delete project?';
  static const deleteUndoNote = 'This cannot be undone.';
  static const taskDeleted = 'Task deleted';
  static const projectDeleted = 'Project deleted';
  static const projectActionsTooltip = 'Project actions';
  static const errorUnknownTask = 'That task no longer exists.';
  static const errorDeleteFailed = 'Could not delete. Nothing was changed.';
  static const errorLastProject = 'Keep at least one project.';
  static const themeLabel = 'Theme';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const themeSystem = 'System';
  static const subtasksHeader = 'Subtasks';
  static const metricDueToday = 'Due today';
  static const metricOverdue = 'Overdue';
  static const metricInProgress = 'In progress';
  static const metricProgress = 'Progress';

  static const filterAll = 'All';
  static const filterLabel = 'Filter by status';
  static const quickAddHint = 'Add a task and press Enter';
  static const quickAddLabel = 'Quick add';

  static String filterChipLabel(String label, int count) => '$label $count';

  static String deleteTaskBody(int subtaskCount) {
    if (subtaskCount == 0) {
      return deleteUndoNote;
    }
    final noun = subtaskCount == 1 ? 'subtask' : 'subtasks';
    return 'This also deletes $subtaskCount $noun. $deleteUndoNote';
  }

  static String deleteProjectBody(int taskCount) {
    if (taskCount == 0) {
      return 'This deletes the project. $deleteUndoNote';
    }
    final noun = taskCount == 1 ? 'task' : 'tasks';
    return 'This deletes the project and its $taskCount $noun. $deleteUndoNote';
  }

  static String progressLabel(int done, int total) => '$done of $total done';

  static String themeLabelOf(ThemePreference preference) {
    return switch (preference) {
      ThemePreference.light => themeLight,
      ThemePreference.dark => themeDark,
      ThemePreference.system => themeSystem,
    };
  }

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
      WorkspaceError.unknownTask => errorUnknownTask,
      WorkspaceError.deleteFailed => errorDeleteFailed,
      WorkspaceError.lastProject => errorLastProject,
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
