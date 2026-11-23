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

## 9. Next build 1.1.0+2: sign-in and synchronization, synchronized due times, hierarchy interactions
Baseline at the start (head `c726b48`, Linux, the two-device e2e enabled against a local PostgreSQL 16): 965 passed, 25 skipped, 26 failed. The 26 are the known platform-specific set: 22 golden comparisons (Windows renders), `workspace_sqlite_test` "database location" (Windows path separators), `S8-03`, `S8-09`, `S8-10` (in-memory secure store off Windows). SQL baseline: every suite in `supabase/tests/run_local.sh` passed.

### 9.1 What was implemented
| # | Item | Result |
|---|---|---|
| 1 | Sign-in and synchronization build | The build already existed (`windows-sync-dev-build.yml`, `NEXORA_SYNC=true`, public TEST URL and anon key, no secret); it was not rebuilt. Version raised to **1.1.0+2**; the workflow also starts on a push to this branch that touches it; `BUILD-INFO.json` gains `syncEnabled`; About shows **Synchronization On/Off** next to the build type, so a DEVELOPMENT TEST sync build and a local-only build cannot be confused (`versioning-and-build-identity.md` section 0). Local and account workspaces, per-account files, the preview-first import, the unsaved-edit gates and conflict handling are unchanged (the existing runtime, import and conflict suites pass). |
| 2 | Synchronized optional due times | Local schema 6 (`tasks.due_time`, migrates version 5 times in place); `due_time` in the patch, pull, restore, merge and conflict code; capability from the server's `features` answer (remembered offline); pairing of date and time; **hosted migration `20261116100000_nexora_due_time.sql` prepared, rolled back and tested on a disposable database, NOT applied** (`due-time-hosted-migration.md`). Date-only stays date-only; Today and Overdue stay date-based (ADR 0004 section 5.7). |
| 2b | Import | The preview states how many tasks have a time and, while the server cannot store times, that they are imported with the date only; with a migrated server times are kept. |
| 3 | New subtask dialog | The parent sits in a framed accent card (icon, heavier label, bold selected text with its ancestry), current task preselected, other valid parents of the same project selectable. |
| 4 | Default expansion | A parent at the top of the current list shows its direct children, once (`expansionDefaulted`); never recursive; an explicit collapse survives refresh, sort, search, filter and view changes; a parent that gains its first child opens; a fresh load starts again. |
| 5 | Related subtask | `revealSubtask`: every collapsed ancestor opens, the task is selected through the unsaved-change gate, the list takes focus and scrolls to the row. Search, filters and view are never cleared; when they hide the task, the list says why and offers one explicit action per cause (Show in project, Clear search, Show all statuses, Expand parents). A selection that was already hidden is kept when the user widens one of them. |
| 6 | New task dialog | Project first, then Title; Tab order Project, Title, Cancel, Create; the title still has the initial focus (type and Enter), the default project is unchanged. |
| 7 | Regression checks | Stale-UI behaviour covered by `workspace_refresh_test` and the runtime refresh tests (verified in a real sync-enabled build only after the hosted gate and a Windows run: F12); Ctrl+F by `ctrl_f_focus_test`, real keyboard not run (F19); manual expansion, keyboard, search, filter and sort rules together in `default_expansion_test` and the UI tests. |

### 9.2 Existing tests changed (forced by the design)
| Test | Change | Why |
|---|---|---|
| `task_workspace_editing_test` (2), `task_workspace_navigation_test`, `task_workspace_transaction_test`, `tasks_notifier_test`, `keyboard_test` (3), `task_tree_test` (3) | parents are expanded by default, so tests that started from "collapsed" now collapse first or drop the first toggle; the list tests' viewport is taller | default expansion (item 4) |
| `reminder_store_test` (4) | schema 6; stepped-back file drops the column | schema 6 |
| `due_time_sqlite_test` | rewritten for the column, migration from 5 and 4, and the wire | schema 6 |
| `panel_resize_test` | Tab loop allows more stops | more rows are visible by default |
| `supabase/tests/s2_auth_grants_test.sql`, `s2_device_test.sql`, `verify_rollbacks.sh` | the ACL matrix lists the new private helper; the registration answer may carry `features`; the old rollback chain skips the new migration | the migration adds a helper and a key |
| `test/support/fake_sync_server.dart`, `workspace_harness.dart` | `features` answer; `dueTimeSupportOf` | capability |

### 9.3 Verification (local; what was run, exact numbers)
| Check | Result |
|---|---|
| `flutter analyze`, `dart format --set-exit-if-changed .` | clean |
| `flutter test` (Linux, Flutter 3.47.9, e2e against local PostgreSQL 16) | **1053 passed, 25 skipped, 26 failed**; the 26 are exactly the baseline set |
| New Dart tests | `due_time_sync_test` (17, two devices on the migrated server), `default_expansion_test`, `reveal_subtask_test`, `reveal_subtask_ui_test`, `create_dialogs_test`, additions to `import_ui_test`, `sync_runtime_test`, `about_test`, `task_workspace_editing_test`, `due_time_sqlite_test` |
| SQL (`run_local.sh`, PostgreSQL 16; CI uses 17) | **ALL SUITES PASSED**, including `due_time_test.sql` (47 assertions); `verify_due_time_migration.sh` all PASS; `verify_rollbacks.sh` ALL PASSED |
| Goldens | 17 of 22 render differently from the head `c726b48` (default expansion and the new list layout; the four Dashboard goldens and the empty state are unchanged). **They must be regenerated on the Windows runner** (workflow `regenerate-goldens`); not done here |
| Windows C++ and the Windows GUI | not compiled/run here; CI builds it |
| Hosted Supabase | **not touched**; no test wrote to it |

### 9.4 Blocked or waiting
The hosted due-time migration (owner approval of the exact operation); Windows acceptance rows F10 to F20; regenerated goldens; a real sync-enabled run against the TEST project (needs the migration for the time, and the account for everything else).

## 10. Unsaved edits on exit, and the live-acceptance UI refinements (same branch, same Draft PR)

### 10.1 The confirmed finding: unsaved edits lost on exit (build 1.1.0+2, commit `8fe2d59`)
Two separate causes, one per way of leaving the application.
- **Title-bar X.** The window's WM_CLOSE goes to the Flutter engine, which asks the framework (`AppLifecycleListener.onExitRequested`). `UnsavedChangesHost` owned that listener, but declared it as `late final AppLifecycleListener _lifecycle = AppLifecycleListener(...)`. A `late final` initializer runs on first use, and the first use was `dispose()`: the listener was **never registered**, so the engine got the default answer ("exit") with a dirty draft. The earlier tests called `handleExitRequest()` directly and never proved the registration. Fix: create it in `initState`.
- **Tray Exit.** The native menu item sends `exitRequested`; `DesktopBridge` ran `beforeExit` and `quit()` without asking the workspace. Fix: it now calls `TasksNotifier.requestExit()` first. A clean workspace exits as before. A dirty one opens the **same** unsaved-changes dialog as the X (Save, Discard, Cancel; a failed save keeps the dialog and the draft), and the process ends only from Save or Discard through the same close sequence (`finishExit`: `beforeExit`, then native `quit`). Cancel keeps the app and the draft.
- **Native side (needs the Windows build to confirm).** The native 4 s forced-quit timer would have ended the app while the dialog waited, so Dart calls the new `holdExit` method, which stops the timer and shows the window (it may sit in the tray). After the gate, `quit()` marks the runner as quitting and WM_CLOSE then destroys the window directly instead of asking Dart again after the runtime is closed.
- **Behaviour summary.** The title-bar X is an exit, not a hide-to-tray (only minimize hides to the tray); with unsaved edits it cancels the close and shows the dialog. Minimize to the tray keeps the draft in memory and intact; restoring the window shows it, and a later real exit is gated. A second exit request while the dialog is open adds no second dialog. All draft fields are covered (`EditDraft.isDirty`: title, status, priority, due date, due time, notes).

### 10.2 UI refinements
| Item | Change |
|---|---|
| A. Panel widths | Remembered per device in `settings.json` (key `panel_widths`, same file as the theme and the window placement), written about 0.4 s after the last change and on dispose; restored at start, clamped to the limits and fitted to the window each build (the stored choice is kept when the window is small). A reset is saved. Code: `lib/platform/panel_width_store.dart`, `app_shell.dart`. |
| B. Hidden-task notice | A solid banner with an accent edge, an icon, the cause in words, and filled action buttons (same keys and actions); nothing is cleared by itself. |
| C. Pickers | Project and parent pickers: menu height limited to 264 px (longer lists scroll), dialog-family colour and radius. Same widgets and keys, so keyboard use, the same-project restriction and focus are unchanged. A true bordered popup would need a different widget; not done. |
| D. Notes matches | A task found only through its Notes shows "In notes: ...excerpt..." with the match emphasised, one line, tooltip with the excerpt, part of the row's semantics label. `notesMatchExcerpt` uses the same test as `matchesSearch`; which tasks match is unchanged. |
| E. Narrow widths | Reminder strip: below 760 px it stacks (name on its own two lines, state and actions wrap below); wide layout unchanged; tooltip with the whole name. Sidebar: tooltips with the whole project name and the account text; sync card: title may use two lines and the action drops under it when both do not fit. |
| F. Second launch | The second process calls `AllowSetForegroundWindow` for the running instance before asking it to show itself. This is the documented way for the process the user just started to pass the foreground right on. Windows may still refuse; then the window is restored and its taskbar button flashes, as before. **Not verified on Windows.** |

### 10.3 Tests
New: `test/app/exit_unsaved_test.dart` (15; drives `WidgetsBinding.handleRequestAppExit`, the call the engine makes for the X, and the tray `ExitRequested`; Save, Discard, Cancel, failed save and retry, no stacked dialogs, all draft fields), `test/platform/panel_width_store_test.dart` (6), `remembered widths` group in `panel_resize_test.dart` (7), notice tests in `reveal_subtask_ui_test.dart`, picker tests in `create_dialogs_test.dart`, `notesMatchExcerpt` tests in `task_search_test.dart`, `test/app/search_notes_match_test.dart`, strip tests in `reminder_ui_test.dart`, `test/app/narrow_sidebar_test.dart`. With the old `unsaved_changes_host.dart` the two X tests fail; with the fix they pass.

### 10.4 Not checked here
Windows C++ (compiled by CI only), every Windows GUI behaviour above, the full acceptance matrix. Goldens: CI run 45200287857 on `41b33c9` failed exactly the four `alert bar` goldens (the sync card action moved under the title); they were regenerated on the Windows runner (run 45202258519), the other 18 came out byte-identical, and the four new images are committed. See `phase-5-acceptance.md` rows F21 to F30.

### 10.5 Windows CI evidence for this round (automated; not a GUI observation)
CI run 45203271612 on head `8a1325e` (Windows runner): format, analyze, **1102 tests passed, 59 skipped** (all 22 goldens included), cross-process SQLite restart check, **Windows release build (the changed C++ compiled)**, shell-integration smoke against the real `nexora.exe` (second launch exits and leaves one process, minimize to the tray, restore, **tray Exit terminates the process** with a clean workspace), portable ZIP smoke. The smoke script has no unsaved draft, so it proves that the changed quit path (`quitting_` then WM_CLOSE then DestroyWindow) still ends the process, not that the dialog appears. The first run on `41b33c9` failed only the four alert-bar goldens (fixed above). What the smoke cannot show is unchanged: dialog on X and tray Exit, foreground behaviour (F29), and every other GUI row stay **not run**.

