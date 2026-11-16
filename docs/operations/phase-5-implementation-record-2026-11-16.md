# Phase 5: UI/UX modernization, Midnight (implementation record)

Status of the phase and its gates: `docs/coordination/status-register.md`. Decisions: `docs/architecture/decisions/0003-phase-5-ui-ux.md`. Baseline: `main` at `bc12b30` (Phase 4 merged). Branch: `feature/phase-5-ui-ux`. No hosted Supabase change was made or is needed; nothing is merged without owner approval.

## 1. Work packages
| Package | Contents | Kind |
|---|---|---|
| 0 Preparation | Branch from `main`. Baseline: 671 tests passed, 1 environment failure (`secure_store_test` "real DPAPI" through the PowerShell fallback; fails the same on a clean `main` in this development machine). PR #15/#16 reviewed: theme controller, theme scope, settings store, file settings store and the bundled fonts reused; everything else written against `main`. | none |
| 1 Foundation | `NexoraTokenSet`/`NexoraColors` (21 tokens, Dark and Light), `buildNexoraTheme`, `NexoraText` type styles, component themes, bundled fonts, `ThemeController`, System mode, contrast test for both palettes. | presentation + theme preference |
| 2 Workspace | `AppShell`, sidebar (brand, Views, Projects, project colour dots), list header, tools row, list card, `TaskRow` (guide lines, status ring and badge, metadata order, per-row focus ring, context text, friendly dates), `DetailsPane` (pinned save bar, task group, subtask rows), dialog theming, empty states. | presentation |
| 3 Status, account, reminders | `describeSync`, `SyncCard`, `SyncAlertBar`, `AccountMenu` (sync-disabled variant), session notices as snackbars, reminder block with the inline editor, `ReminderStrip`. | presentation |
| 4 Views and input | `DashboardPane`, status filter, quick add. | functional |
| 5 Delete | Delete task and delete project (repository capability, workspace, confirm dialog, reminder cancellation, tests). | functional |
| 6 Acceptance | Tests, goldens, docs, CI, Windows DEVELOPMENT TEST build, Draft PR. | none |

## 2. Presentation changes and functional additions
Presentation (behaviour of `main` unchanged): shell, sidebar, task list, task row, details pane, reminder block and strip, account and sync card, dialogs, empty states, keyboard map, gate, breakpoints.
Functional: theme Light/Dark/System (per device file), Dashboard view, status filter, quick add, delete task, delete project, severity-based sync card and alert bar, account menu, inline reminder date and time editor, plus the sign-out gate (ADR 0003, decision 7). Not in Phase 5: a separate Description field, a full Settings screen, final brand artwork.

## 3. Existing tests whose assertions changed (forced by the approved design)
| Test | Change | Why |
|---|---|---|
| `task_tree_test` "a row shows status, due date and priority" | expects `AppStrings.friendlyDue(...)` instead of `Due 2026-11-10` | friendly dates in rows are approved; ISO stays in the conflict dialog |
| `accessibility_test` chevron size | 30 x 30 instead of 40 x 40 | the spec fixes a 24 px chevron box; 30 px is the pointer target-size floor used by the design |
| `reminder_ui_test` (4 tests) | snooze is a menu on the strip; the inline editor replaces the two pickers; the friendly time form; the device-only wording is a tag plus a helper line | approved reminder block and strip |
| `app_host_signin_test` (2 tests) | Sign out is opened from the account menu | account actions moved into the sidebar menu |
| `conflict_runtime_test` | the conflict sentence is found on the card and on the alert bar (`findsWidgets`) | the sentence is shown in both places by design |
| goldens `all_view_selected`, `empty_state` | regenerated | restyle |

Every other existing test passes unchanged.

## 4. New tests
`test/app/sync_presentation_test.dart` (ten rows and the precedence), `test/app/phase5_ui_test.dart` (sync-disabled card and menu, alert bar present for four states and absent otherwise or without a panel, save bar, gate additions for dashboard, sign-out and subtask rows, focus ring, context text, theme change leaves selection and draft, status filter, quick add, delete dialogs, dashboard counts), `test/app/reminder_ui_test.dart` (reminder isolation from the draft, inline editor one call, past time keeps the editor open, Cancel makes no call, deleting a task cancels its reminder), `test/features/tasks/application/task_workspace_phase5_test.dart` (friendly dates, status filter, dashboard and sign-out gate, delete rules), `test/features/tasks/application/visibility_regression_test.dart` (rows of every view, project, search and sort identical to a baseline recorded on `main`: `test/fixtures/phase5/visibility_baseline.txt`), `test/features/tasks/data/workspace_delete_sqlite_test.dart` (tombstones, one delete operation listing the subtree), `test/features/tasks/presentation/contrast_test.dart` (both palettes, including `onSeverity`), `theme_controller_test.dart`, `test/features/tasks/data/file_settings_store_test.dart`, goldens `test/golden/phase5_golden_test.dart` (1366x768 and 1024x768, Dark and Light: workspace, dashboard, details, gate dialog, alert bar).

## 5. Technical review points of the handoff
- **Delete and synchronization:** verified on `main` (`softDeleteTaskTree`, `softDeleteProjectTree`, `OutboxStore.recordDeleteTree`, S3 atomic subtree delete, two-device E2E and HTTP tests). One delete operation lists the subtree (new SQLite test).
- **Reminders of deleted tasks:** cancelled for the task and every subtask when the user deletes (new test); the reminder service also acknowledges reminders of tasks that no longer exist on its next tick.
- **Session notices:** `signedOut`, `anonymousRejected` and `storageProblem` are snackbars; `sessionExpired` is the Sign in needed state (card and bar).
- **Reminder banner:** the strip keeps the first due task, "+N more" (opens the dashboard), Open, Snooze, Done and the native-unavailable note; "Dismiss all" is on the dashboard panel.
- **Dashboard selection:** `NavSelection` is not persisted and the smart-view counting code is unchanged (`inSelection` is false for it).
- **Widget keys:** the existing keys were kept on the widgets that play the same role (`sync-status-bar` is now the sync card; `reminder-banner` is the strip); new keys are listed in the tests.
- **Fonts and size:** two variable fonts (about 300 KB) are added to the bundle.

## 6. Environment limits of the development machine
Flutter 3.47.9 / Dart 3.13.7 (the CI pin) was installed for this work. The machine has no "Desktop development with C++" components for Visual Studio, so the Windows runner is not built locally; the portable build is produced by CI (`windows-sync-dev-build`). Goldens are generated on Windows; the pinned Windows runner re-checks them.

## 7. Evidence
Local: `flutter analyze` clean; full `flutter test` run recorded in the pull request. CI run ids for the exact head and the DEVELOPMENT TEST build artifact are in the pull request description.
