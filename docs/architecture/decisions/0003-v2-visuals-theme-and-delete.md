# 0003 Nexora V2: visuals, theme preference and delete

Status: implemented in a working copy. Format, analyze and all tests pass locally (Flutter 3.47.9). Not yet run in CI or launched as a Windows app.

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
- `SettingsStore` (application) and `SqliteSettingsStore` (data) keep `Light | Dark | System` in the existing `meta` table under `theme_preference`. No schema change, no outbox entry: it is local to the device and never syncs.
- `ThemeController` is separate from `TaskWorkspace`, so a theme change never touches selection, drafts or the unsaved-change gate. `System` maps to `ThemeMode.system`, which follows Windows and updates while the app runs.

## Delete
- `TaskRepository` gains `deleteTasks(idsLeafFirst)` and `deleteProject(projectId, idsLeafFirst)`. Both are one transaction, soft (tombstone), and queue `delete` operations in leaf-first order, then the project last, as decision D-P requires. A tombstone cannot be restored (D-T, D-E).
- `leafFirstDeletionOrder` and `projectDeletionOrder` (domain) compute the order.
- `TaskWorkspace.requestDeleteTask` and `requestDeleteProject`: refused while a change runs or the gate is open; blocked by a dirty draft of a task outside the deleted tree; a dirty draft inside the tree is dropped with it. The last remaining project cannot be deleted. A failure changes nothing.
- UI: a confirm dialog states how many subtasks or tasks go too and that it cannot be undone. Task: "Delete task" in the details panel. Project: the menu on a project tile.
- This closes REQ-6 on the client side (leaf-first tombstones). Server enforcement is still Phase 3.
- No keyboard shortcut was added for delete.

## Not built (needs owner decision)
- A separate Description field (needs a schema change); the editor keeps one Notes field.
- Settings screen, sync status and the conflict Resolve flow (Phase 3). The sidebar shows "Saved on this device".
