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

## 8. Follow-up: UI/UX and reliability fixes (same branch, same Draft PR)
Scope: eight items reported after the first Windows look. No hosted change, no schema change on the server, no change to the outbox, pull or conflict contracts. Dashboard visual redesign and new statistics are not part of this work. Decisions: `docs/architecture/decisions/0004-due-time-semantics-and-hosted-boundary.md`; build identity: `docs/operations/versioning-and-build-identity.md`. Everything below was verified **on Linux** (Flutter 3.47.9 / Dart 3.13.7, the CI pin) with widget, unit and SQLite tests; **nothing was run on a Windows GUI** (section 8.4).

### 8.1 What changed
| # | Item | Result |
|---|---|---|
| 1 | Stale UI after synchronization | **Root cause (reproduced by a failing test first):** `TaskWorkspace.refresh()` refused to run whenever `draft != null`, but a draft exists for *every selected task*, dirty or not, so any selected task blocked the refresh. The retry in `SyncRuntime` fired only when `draft == null`, which happens when the selection clears, for example when you switch to another project. That is exactly the reported workaround. A second gap: the refresh ran only after a cycle that ended `idle`, although pulled pages are applied as they arrive. Fix: `refresh()` always applies incoming data (lists, counts, Dashboard, which all read `WorkspaceState.tasks`); a clean selected task follows its stored version (selection kept; a deleted one is deselected); a dirty draft is **never overwritten** (untouched fields take the incoming value, edited fields keep the user value, overlapping edits are listed in a banner, Revert loads the incoming version; an incoming delete keeps the edits, refuses Save and Revert leaves the task); a refresh during a save or decision is queued and runs afterwards; a vanished project falls back to All. The runtime refreshes after every finished cycle. The gap in the old rules (no defined outcome for a dirty draft) is closed by this explicit, non-destructive rule. |
| 2 | Due date with optional time | `DueTime` (floating `HH:MM`), `Task.dueTime`, local schema 5 table `task_due_times`, date and time rows, list row `Today · 17:30`, sorting, semantics and time-zone/DST rules in ADR 0004. **Enabled in the local-only workspace; disabled with a visible reason when signed in** because the hosted `due_date` is a `date` and a synchronized time needs a hosted change (ADR 0004 section 6). Date-only stays date-only. |
| 3 | Details hierarchy | Project (one line, tooltip with the full name, semantics label) above the title; due date and time on full-width rows; save bar, dirty state, Save/Revert and the gate unchanged. |
| 4 | Reminder selection | One modal: In 1 / 2 / 5 / 24 hours (shown as concrete date and time, computed from now, elapsed time across DST, seconds rounded up) and Custom date and hour; Cancel and Escape save nothing; invalid and past times give a clear error; the dialog says the reminder is device-local and independent of Save/Revert. Immediate-save semantics unchanged. |
| 5 | Subtask parent | Parent picker preselected to the current task, other tasks of the **same project** (not archived) with their ancestry; project shown as context. Cross-project parenting is **not** offered (`validateParentChange` rejects it and a subtask takes its parent's project). No UI reparents existing tasks, so the self/descendant rule has no entry point; the rule stays in `task_tree_rules.dart`. |
| 6 | Search, filters, panels | Search on its own row; filters and sort wrap beneath (checked at 1920 to 700 px). **Ctrl+F:** the focused test shows it reaches and focuses search from the list, sidebar, filter chips, sort menu, details editor and the overlay layout; the one real defect was the **Dashboard** (no search field, no key scope), now Ctrl+F opens All and focuses search. **Focus indicators:** measured on pixels in both themes; `NavTile` had `focusColor: transparent` (invisible focus in the sidebar), chips, sort button, subtask rows, account row and Dashboard tiles had only a faint wash. A shared `FocusRing` (2 px accent) fixes them. **Panel resizing:** implemented for the three-pane layout (drag and keyboard handles, Tab reachable, Home/double-click reset, 200 to 360 and 340 to 560 px, never below the list minimum so the breakpoints hold; at 1100 px the defaults already use the minimum, so nothing grows there). The overlay (900 to 1099 px) keeps its fixed 380 px. Widths are not persisted (follow-up: a `settings.json` key). |
| 7 | Windows startup window | No window-state mechanism existed (the runner hard-coded 1280x720 at 10,10; the per-device settings file `settings.json` already holds the theme). Added on the existing `nexora/desktop` channel and the existing settings file: first launch opens **maximized** with the normal title bar; later launches restore the last restored bounds and maximized flag; a placement whose title bar is not reachable (monitor removed, layout or resolution changed) is moved onto the best display, centred and clamped. Decision logic is pure Dart and tested; the C++ is thin. |
| 8 | Version and build identity | One source: `pubspec.yaml` (bundled as an asset and read at run time). About in the account menu shows version, short commit, build type (DEVELOPMENT TEST marked) and CI run; a local build shows an explicit unknown commit. CI writes `NEXORA_COMMIT`, `NEXORA_BUILD_TYPE`, `NEXORA_BUILD_RUN` and `BUILD-INFO.json` (inside the ZIP and as an artifact file); a pull request records its **head** commit, not the test-merge commit. ZIP names unchanged. |

### 8.2 Existing tests changed (forced by the design)
| Test | Change | Why |
|---|---|---|
| `workspace_refresh_test` "never replaces the workspace while a draft is open" | replaced by the new incoming-change suite (a dirty draft is still never replaced, but the list now updates) | item 1 |
| `reminder_store_test` (4 tests) | schema version 4 to 5; the stepped-back v3 file also drops `task_due_times`; newer-file test uses 6 | schema 5 (item 2) |
| `reminder_ui_test` | the inline editor became a dialog: tests open it and choose Custom; viewport 1400x1300 (the details pane is taller); Cancel closes the dialog | item 4, item 2 |
| `task_tree_test` (viewport) | 1280x800 to 1280x900 | the search row (item 6) pushes the lazily built list down |
| `test/support/task_fixtures.dart`, `workspace_harness.dart` | `dueTime`, `dueTimeSupported` parameters | item 2 |

### 8.3 New tests (198 more than the baseline run)
`workspace_refresh_test` (incoming creation, update, deletion, selected task, no navigation, unsaved edits, queued refresh, unreadable store, vanished project), `due_time_test`, `due_time_sqlite_test`, `details_due_time_test` (full date at 1400/1100/1000/900 px in both themes and at 150 % text, time controls, hierarchy, long project name, pinned save bar, incoming banner), `reminder_presets_test` and the `reminder dialog` group in `reminder_ui_test`, `parent_choices_test`, `subtask_parent_test`, `ctrl_f_focus_test`, `list_tools_layout_test`, `focus_visible_test` (pixel check, both themes), `panel_resize_test`, `window_placement_test`, `build_info_test`, `about_test`.

### 8.4 Verification results and what was NOT checked
| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `dart format --output=none --set-exit-if-changed .` | 0 changed |
| `flutter test` (Linux, Flutter 3.47.9) | **945 passed, 45 skipped, 26 failed** |
| Baseline before any change (same branch head `a2ef997`, Linux) | 747 passed, 45 skipped, 26 failed |
| The 26 failures | identical in the baseline and on a clean `main` (`bc12b30`) checkout for the three non-golden groups: 22 golden comparisons (the goldens were rendered on Windows; Linux differs by 0.65 % of pixels), `workspace_sqlite_test` "database location" (hard-codes Windows path separators), and `S8-03`, `S8-09`, `S8-10` (use `InMemorySecureStore` off Windows, so a restart loses the session). The local DPAPI test is skipped on Linux; the historical Windows result is not a substitute and was not re-run. |
| Goldens | **18 of the 22 goldens render differently after this work** (all except the four Dashboard ones: the search row and details pane changed). Verified by rendering both versions on Linux. They **must be regenerated on Windows** (`flutter test --update-goldens test/golden` on the pinned runner or the development machine) before the Windows CI golden step can pass; I did not regenerate them (Linux output would not match Windows). |
| Windows native code (window placement, first-frame show, channel methods) | **Not compiled and not run.** The runner needs the Windows toolchain; CI builds it. The Dart side and the decision logic are tested. |
| Real Windows notification | not tested |
| Windows GUI acceptance (Dark and Light, 100 % and 150 %, the five window sizes, real Ctrl+F keyboard interaction) | **not run**; no Windows machine here. Supporting renders (Linux, real bundled fonts, not Windows): `docs/operations/evidence/phase-5-followup/` |
| Hosted Supabase | not touched; no test wrote to it |

