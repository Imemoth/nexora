/// Stable error codes for the workspace. Presentation maps each code to text.
enum WorkspaceError {
  titleRequired,
  titleTooLong,
  unknownProject,
  unknownParent,
  parentArchived,
  saveFailed,
  loadFailed,

  /// A creation was requested while an unsaved-change decision is open.
  unsavedChangesPending,
}
