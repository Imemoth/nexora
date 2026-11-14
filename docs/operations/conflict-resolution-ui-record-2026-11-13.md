# V1 conflict resolution experience (2026-11-13)

Trigger: in the owner's two-device Windows test the status bar said "1 conflict needs your decision" but the text was passive. The engine already resolved conflicts (`SyncEngine.resolveConflict`); no screen was connected to it. No hosted schema, Auth or server change was made.

## 1. What the user sees
1. **Status bar:** when conflicts exist (and the account is signed in) the passive text is replaced by a prominent, keyboard-focusable button with a warning icon and the count ("2 conflicts need your decision", tooltip "Review and resolve the conflicts", screen-reader label). **Sync now** stays next to it.
2. **Resolve conflicts dialog** (opens from the button): a list on the left (task or project name, project, the differing fields, status) and the selected conflict on the right. Several conflicts are supported; resolving one moves the selection to the next and the dialog says "All conflicts are resolved." when none are left.
3. **Side-by-side comparison:** "Your version (this device)" on the left, "Server version" on the right, one row per conflicting field (Title, Notes, Status, Priority, Due date, Parent task, Order...). Differing rows are tinted and marked "Differs". A side that is deleted shows "Deleted"; a value the stored evidence does not contain shows "Not recorded" (nothing is invented). Statuses and priorities are in words; a parent shows the parent's title. No JSON is shown.
4. **Decisions** (only the valid ones for the conflict, with a one-line explanation each; pinned below the scrolling comparison):
   | Conflict | Offered |
   |---|---|
   | same field(s) changed on two devices (`field`, `exists`) | Use server version, Keep my version, Merge selected fields (only when two or more fields differ) |
   | I edited, the server item was deleted (`edit_deleted`) | Accept the deletion, Keep my changes as a new copy |
   | I deleted, the server item was edited (`delete_edited`) | Keep the item (server version), Delete it anyway (my version) |
   | I deleted a parent, children were added elsewhere (`parent_has_live_children`) | Keep the item; "Delete it anyway" only for a tree delete |
   | already decided on another device | Use server version, Keep my version (applied locally, no second server decision) |
   Merge shows a Mine / Server choice per field and enables the button only when every field has a pick.
5. **Confirmation:** every choice that discards a local or a server change asks first ("Use the server version? Your version of the conflicting fields will be discarded on this device." etc.). "Keep as a new copy" discards nothing and asks nothing.

## 2. How it is built
* `lib/features/sync/conflicts.dart`: `ConflictService` (list, resolve) and the view models (`ConflictView`, `ConflictFieldView`, `ConflictSide`, `ConflictOutcome`). It reads the stored evidence (`sync_conflicts_local`, the last server snapshot, the local rows) and calls the **existing** `SyncEngine.resolveConflict`; widgets never read tables (the architecture tests still pass).
* `lib/app/conflict_panel.dart` (abstraction), `lib/app/conflict_dialog.dart` (UI), `lib/app/sync_panel.dart` (indicator), wired through `SyncRuntime.conflictPanel()`, `AppHost`, `NexoraApp`, `AppShell`.
* `SyncStatus.openConflicts` now counts every conflict that still waits for the user, including one another device already decided on the server (its local change still needs a decision here).
* After a confirmed decision the runtime refreshes the workspace, queues synchronization again, and the engine updates the status bar; the dialog reloads from the local file.

## 3. Failure handling (nothing is lost, no early success)
| Situation | Result |
|---|---|
| offline | "No connection. Nothing was changed..."; conflict, local change and evidence stay; retry works |
| expired sign-in | "Sign in again ..."; nothing changed |
| revoked device | "This device was removed from the account ..."; nothing changed |
| server refuses | "The server refused this decision (code) ..."; nothing changed |
| second click while sending | refused ("already being sent"); the server gets one request |
| conflict already decided elsewhere | "Another device already decided this conflict. Updating..." then the conflict is listed as decided elsewhere with local choices |
| app restart during resolution | the conflict and its evidence are in the local file; the engine reuses the stored operation id, so the server applies the decision once |
| unexpected error | contained, "Something went wrong. Nothing was changed. Try again." |
The success state is shown only after the engine returns, which is after the server confirmed.

## 4. Tests (all run in CI)
* `test/features/sync/conflict_service_test.dart` (19): listing and comparison, every strategy, invalid strategy, missing picks, duplicates, offline and retry, auth, revoked, rejection, signed out, decided elsewhere, restart.
* `test/app/conflict_ui_test.dart` (19): clickable and keyboard-activated indicator, list navigation, comparison and highlighting, valid choices only, confirmation and cancel, merge picks, copy without confirmation, in-flight state, every failure message, automatic refresh.
* `test/runtime/conflict_runtime_test.dart` (5): the owner scenario through the runtime and through the real window (open, compare, decide, confirm, both devices converge), use server, offline then restart then retry.
* `test/e2e/two_device_sync_test.dart` (+6): keep mine, use server, merge, recreate copy, decided elsewhere, restart, against the real PostgreSQL server.

## 5. Owner acceptance path
Install the new DEVELOPMENT TEST build. With the existing unresolved conflict: (1) press the red-tinted "1 conflict needs your decision" button; (2) read your version and the server version of the title; (3) choose Keep my version or Use server version; (4) confirm; (5) the conflict disappears; (6) press Sync now on both devices: both show the chosen value.
