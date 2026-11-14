# 0003 Nexora V2: visuals, theme preference and delete

Status: ported onto the sync branch (schema 3, accounts, sync, conflict UI). Format, analyze and the tests pass locally except an environment-specific DPAPI test (see the pull request). Not yet launched as a Windows app.

## Visuals
- Two approved themes, dark and light, built from `NexoraPalette.dark` and `NexoraPalette.light` (`presentation/theme/palette.dart`). `NexoraColors` (a `ThemeExtension`) carries the semantic colours and gradients to widgets.
- `buildNexoraTheme(Brightness)` maps the tokens to `ThemeData`, including buttons, inputs, dialogs and menus.
- `border-strong` and the light `accent-cyan` were adjusted from the approved canvas so that control borders and links meet 3:1 and 4.5:1. `contrast_test.dart` checks both themes.
- Fonts: Manrope and Space Grotesk are bundled in `assets/fonts` (variable fonts from the Google Fonts repository, SIL Open Font License; licence files sit beside them) and declared in `pubspec.yaml`, one entry per weight. Segoe UI is the fallback. Not yet seen rendering in the running Windows app: confirm that weights 400 to 700 look right.

## Status filter and quick add
- `WorkspaceState.statusFilter` and `TaskWorkspace.requestStatusFilter`. Like sorting, the filter is never gated and never touches the draft. A selected task it hides stays selected and the existing "hidden in this view" notice shows. Creating a task the filter would hide clears the filter so the new task is visible.
- Filter chips (All plus one per status) show the count each would list for the current view and search.
- `QuickAddField` creates a root task through the same path as the New task dialog (selected project, or the first project from a smart view), so every rule and the unsaved-change gate apply.
- The dashboard, chips and quick add scroll with the list, so they do not take room from the rows.

## Theme preference
- `SettingsStore` (application) and `FileSettingsStore` (data) keep `Light | Dark | System` in `settings.json` beside the local database. It is a file, not a database row, because a signed-in account opens its own database and the theme belongs to the device. No schema change, no outbox entry, never synced. `AppHost` receives the controller so an account switch keeps the theme.
- `ThemeController` is separate from `TaskWorkspace`, so a theme change never touches selection, drafts or the unsaved-change gate. `System` maps to `ThemeMode.system`, which follows Windows and updates while the app runs.

## Delete
- `TaskRepository` gains `deleteTaskTree(id)` and `deleteProjectTree(id)`. `SqliteTaskRepository` answers them with the existing atomic `softDeleteTaskTree` and `softDeleteProjectTree`: one transaction, soft (tombstone), and for synchronized rows one delete operation that lists the whole subtree, which the server applies completely or not at all (S3). The earlier per-row leaf-first design was dropped on this branch because it would have bypassed `sync_scope` and the outbox rules. A tombstone cannot be restored (D-T, D-E). The repository refuses more than 1,000 descendants, which the UI reports as "Could not delete".
- `leafFirstDeletionOrder` and `projectDeletionOrder` (domain) tell the workspace which tasks a delete removes, for the dialog counts, the dirty-draft check and the state update. They do not write anything.
- `TaskWorkspace.requestDeleteTask` and `requestDeleteProject`: refused while a change runs or the gate is open; blocked by a dirty draft of a task outside the deleted tree; a dirty draft inside the tree is dropped with it. The last remaining project cannot be deleted. A failure changes nothing.
- UI: a confirm dialog states how many subtasks or tasks go too and that it cannot be undone. Task: "Delete task" in the details panel. Project: the menu on a project tile.
- The unsaved-change gate, the conflict UI and sync are unchanged. No keyboard shortcut was added for delete.

## Not built (needs owner decision)
- A separate Description field (needs a schema change); the editor keeps one Notes field.
- A Settings screen: the theme selector sits in the list header. The account bar, sync status bar and conflict screens come from the sync work. They pick up the V2 theme through `ThemeData` but were not restyled one by one.
