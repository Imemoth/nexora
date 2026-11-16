import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
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
  // About.
  static const aboutAction = 'About Nexora';
  static const aboutTitle = 'About Nexora';
  static const aboutVersion = 'Version';
  static const aboutCommit = 'Source commit';
  static const aboutBuild = 'Build';
  static const aboutRun = 'CI run';
  static const buildTypeRelease = 'Release build';
  static const buildTypeDevelopmentTest = 'DEVELOPMENT TEST';
  static const buildTypeLocal = 'Local build (not made by CI)';
  static const commitUnknown = 'unknown';
  static const aboutCopy = 'Copy details';
  static const aboutCopied = 'Copied to the clipboard';
  static const aboutClose = 'Close';
  static const aboutDevelopmentNote =
      'This is a development build against the TEST project. It is not a release.';
  static const aboutLocalNote =
      'Built outside CI, so the commit cannot be confirmed.';
  static const resizeSidebar = 'Resize sidebar';
  static const resizeDetails = 'Resize details panel';
  static const resizeHint =
      'Drag, or use the left and right arrow keys. Home restores the default.';
  static const fieldParentTask = 'Parent task';
  static const parentHelp =
      'The subtask stays in the same project as its parent.';
  static String parentChoiceSummary(List<String> path) => path.join(' › ');
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
  static const errorDeleteFailed = 'Could not delete. Nothing was changed.';
  static const errorLastProject = 'The last project cannot be deleted.';
  static const errorTaskDeletedElsewhere =
      'This task was deleted on another device, so it cannot be saved. Revert to leave it.';
  static const defaultProjectName = 'Inbox';

  // Incoming changes while editing.
  static const incomingUpdatedTitle = 'Changed on another device';
  static const incomingUpdatedBody =
      'Fields you did not edit were updated. Your edits are kept.';
  static String incomingOverlapBody(String fields) =>
      'You also edited $fields, which changed elsewhere. Saving keeps your '
      'version; Revert loads the incoming one.';
  static const incomingDeletedTitle = 'Deleted on another device';
  static const incomingDeletedBody =
      'Your unsaved edits are kept here but cannot be saved. Revert to leave '
      'the task.';
  static String incomingFieldName(String field) => switch (field) {
    'title' => 'Title',
    'status' => 'Status',
    'priority' => 'Priority',
    'dueDate' => 'Due date',
    'dueTime' => 'Due time',
    'notes' => 'Notes',
    _ => field,
  };

  // Due date and optional time.
  static const fieldDueDate = 'Due date';
  static const fieldDueTime = 'Time (optional)';
  static const noDueTime = 'No time';
  static const addDueTime = 'Add time';
  static const pickDueTime = 'Pick time';
  static const clearDueTime = 'Remove time';
  static const dueTimeNeedsDate = 'Choose a date first.';
  static const dueTimeLocalOnly =
      'Time of day is not synchronized yet, so it is off while signed in.';
  static const dueTimeHelp =
      'The date alone means the whole day. A time is a wall-clock time and '
      'never shifts with time zones.';
  static const clearDueDateHelp = 'Clearing the date also removes the time.';
  static String dueTimeLabel(DueTime time) => time.toHm();
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

  // Phase 5 (Midnight) strings.
  static const brandMark = 'N';
  static const deleteAction = 'Delete';
  static const deleteTaskAction = 'Delete task';
  static const deleteProjectAction = 'Delete project';
  static const deleteTaskTitle = 'Delete task';
  static const deleteProjectTitle = 'Delete project';
  static const taskDeleted = 'Task deleted';
  static const projectDeleted = 'Project deleted';
  static const deleteUndone = 'This cannot be undone.';
  static String deleteTaskBody(int subtasks) => subtasks == 0
      ? 'This task will be deleted. $deleteUndone'
      : subtasks == 1
      ? 'This task and its 1 subtask will be deleted. $deleteUndone'
      : 'This task and its $subtasks subtasks will be deleted. $deleteUndone';
  static String deleteProjectBody(int tasks) => tasks == 0
      ? 'This project will be deleted. $deleteUndone'
      : tasks == 1
      ? 'This project and its 1 task will be deleted. $deleteUndone'
      : 'This project and its $tasks tasks will be deleted. $deleteUndone';
  static const dashNoteToday = 'due today';
  static const dashNoteOverdue = 'need attention';
  static const dashNoteNext7 = 'coming up';
  static const dashNoteAll = 'in every project';
  static const dashboardTitle = 'Dashboard';
  static const viewsHeader = 'Views';
  static const syncTitleUpToDate = 'Up to date';
  static const syncTitleSyncing = 'Synchronizing…';
  static String syncTitlePending(int n) =>
      n == 1 ? '1 change waiting' : '$n changes waiting';
  static const syncTitleOffline = 'Offline';
  static String syncTitleRejected(int n) =>
      n == 1 ? '1 change refused' : '$n changes refused';
  static String syncTitleConflicts(int n) =>
      n == 1 ? '1 conflict' : '$n conflicts';
  static const syncTitleSignIn = 'Sign in needed';
  static const syncTitleRevoked = 'Device removed';
  static const syncTitleError = 'Sync stopped';
  static const syncTitleLocal = 'Local only';
  static const resolveAction = 'Resolve';
  static const accountLocalShort = 'Local workspace';
  static const themeLabel = 'Theme';
  static const themeSystem = 'System';
  static const themeLight = 'Light';
  static const themeDark = 'Dark';
  static const shortcutsAction = 'Keyboard shortcuts';
  static const shortcutsTitle = 'Keyboard shortcuts';
  static const closeAction = 'Close';
  static const accountMenuTooltip = 'Account and settings';
  static const savedIndicator = 'Saved';
  static const taskGroupCaption = 'Task · saved with Save';
  static const subtasksHeader = 'Subtasks';
  static const needsAttention = 'Needs attention';
  static const nothingDue = 'Nothing is overdue or due today.';
  static const showAll = 'Show all';
  static const selectTaskHint =
      'Use the arrow keys in the list, then Enter to edit.';
  static const dueToday = 'Today';
  static const dueTomorrow = 'Tomorrow';
  static const overduePrefix = 'Overdue';
  static const synchronizationHeader = 'Synchronization';
  static const moreActions = 'More';
  static const noTasksMatchFilter = 'No tasks have this status here';
  static const taskListEmptyNoProject = 'Create a project to add tasks';
  static String quickAddHint(String project) =>
      'Add a task to $project, then press Enter';
  static const quickAddTooltip = 'Add task';
  static const sortPrefix = 'Sort';
  static String sortButton(TaskSort sort) => '$sortPrefix: ${sortLabel(sort)}';
  static String breadcrumbProject(String name) => 'Projects / $name';
  static String breadcrumbView(String name) => 'Views / $name';
  static String summaryLineDone(int done) => '$done done';
  static String summaryLineOverdue(int overdue) => '$overdue overdue';
  static String projectProgress(int done, int total) => '$done/$total done';
  static const contextSeparator = ' › ';
  static const summarySeparator = ' · ';

  /// The keyboard map shown in the "Keyboard shortcuts" dialog: keys, action.
  static const shortcutList = <(String, String)>[
    ('Up / Down', 'Move through tasks'),
    ('Right / Left', 'Expand or collapse a task'),
    ('Enter', 'Edit the selected task title'),
    ('Ctrl F', 'Search'),
    ('Ctrl N', 'New task'),
    ('Ctrl Shift N', 'New subtask'),
    ('Ctrl S', 'Save'),
    ('Esc', 'Clear search, return to the list, then clear the selection'),
  ];
  static const statusFilterAll = 'All';
  static String statusFilterChip(String label, int count) => '$label $count';
  static const stateLabelPrefix = 'Status';
  static const dateLine = 'Today';

  static const monthAbbreviations = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const weekdayAbbreviations = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Weekday, day and month: "Mon 16 Nov". One place to change for later
  /// localization. The ISO form ([dueLabel]) stays for the conflict dialog.
  static String friendlyDate(CalendarDate date) {
    final weekday = DateTime.utc(date.year, date.month, date.day).weekday;
    return '${weekdayAbbreviations[weekday - 1]} ${date.day} '
        '${monthAbbreviations[date.month - 1]}';
  }

  /// How a due date reads in a list: "Today", "Tomorrow", "Mon 16 Nov", or
  /// "Overdue · Thu 12 Nov". A task that is done or archived is never overdue.
  static String friendlyDue(
    CalendarDate due,
    CalendarDate today, {
    required bool closed,
    DueTime? time,
  }) {
    final base = _friendlyDueDate(due, today, closed: closed);
    return time == null ? base : '$base · ${time.toHm()}';
  }

  static String _friendlyDueDate(
    CalendarDate due,
    CalendarDate today, {
    required bool closed,
  }) {
    if (due == today) {
      return dueToday;
    }
    if (due == today.addDays(1)) {
      return dueTomorrow;
    }
    if (!closed && due.compareTo(today) < 0) {
      return '$overduePrefix · ${friendlyDate(due)}';
    }
    return friendlyDate(due);
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
      WorkspaceError.deleteFailed => errorDeleteFailed,
      WorkspaceError.lastProject => errorLastProject,
      WorkspaceError.taskDeletedElsewhere => errorTaskDeletedElsewhere,
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
