/// Why a workspace operation did not happen. The UI maps each to a message.
enum WorkspaceError {
  titleRequired,
  titleTooLong,
  unknownProject,
  unknownParent,
  parentArchived,
  saveFailed,
  loadFailed,

  /// A dirty draft is waiting for Save, Discard or Cancel.
  unsavedChangesPending,

  /// Another change is still running.
  operationInProgress,

  /// The task to delete no longer exists.
  unknownTask,

  /// The delete could not be written. Nothing was changed.
  deleteFailed,

  /// The last remaining project cannot be deleted.
  lastProject,
}
