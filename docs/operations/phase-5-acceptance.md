# Phase 5 Windows visual acceptance (owner checklist)

Status: **open**. Goldens and widget tests do not replace a look at the real application. Acceptance is carried out on the portable ZIP built by CI from `feature/phase-5-ui-ux`: the default build, and the sync-enabled DEVELOPMENT TEST build against the TEST project. Evidence is one screenshot per row and theme stored here, in the form of the Phase 1 acceptance. Gates and register: `docs/coordination/status-register.md`.

Environment: Windows 10 and Windows 11, display scaling 100 % and 150 %, window sizes 1920x1080, 1366x768, 1024x768 and one width below 900 px.

| # | Check in Dark and in Light | Pass when | Dark | Light |
|---|---|---|---|---|
| 1 | Fonts | Manrope and Space Grotesk render at every weight used; no fallback to Segoe UI; no clipped text at 150 % | | |
| 2 | Workspace at each window size | Panes, widths and breakpoints match the prototype; details overlay at 1024; notice below 900 | | |
| 3 | Task tree | Guide lines join between rows; chevrons, rings, badges and metadata align; long titles ellipsize | | |
| 4 | Keyboard | Full shortcut list works; the focus ring is visible on every control and on the active row | | |
| 5 | Editing | Save bar stays pinned; dirty state, Save, Revert and the gate behave as on `main` | | |
| 6 | Reminder | Inline editor, error text, states; a real Windows notification fires; minimize to tray keeps reminders alive; the strip and the dashboard panel update | | |
| 7 | Dashboard | Counts equal the sidebar counts; every tile and row navigates correctly | | |
| 8 | Sync states (sync build) | Up to date, synchronizing, changes waiting, offline (network off), sign-in needed (expired session), conflict (two devices) each show the specified card, and the bar only where specified; device removed and sync stopped where they can be produced, otherwise by widget test | | |
| 9 | Conflict resolution | Dialog readable in both themes; all choices and the confirm step work | | |
| 10 | Account menu | Sync build: theme, import, shortcuts, sign out. Default build: only theme and shortcuts | | |
| 11 | Theme switching | Light, Dark and System switch at once; System follows a Windows theme change while the app runs; the choice survives a restart and an account switch | | |
| 12 | Dialogs, menus, pickers | Create, delete, gate, sign-in, import, sort and snooze menus, date and time pickers are legible in both themes | | |
| 13 | Colour and contrast | No text on a ground it was not specified for; severity bar text is readable; Windows contrast themes do not break the layout | | |
| 14 | Regression | Existing local data opens unchanged; a second instance is refused as before; exit with unsaved edits is gated | | |
| 15 | Delete | Delete task and Delete project ask first, count what goes too, cancel by default; the last project cannot be deleted; a synchronized delete reaches the other device completely | | |

The owner signs off the checklist. Any failed row is fixed on the branch and re-checked in both themes before the pull request is merged.

## Follow-up checks (not part of the 15 rows above; all **not run**)
The 15-row acceptance above is **not** complete and is not marked so. These checks cover the follow-up work (`docs/operations/phase-5-implementation-record-2026-11-16.md`, section 8) and need the CI-built portable ZIP on Windows 10 and 11. Linux widget renders exist as supporting evidence only (`docs/operations/evidence/phase-5-followup/`).

| # | Check (Dark and Light; 100 % and 150 %; 1920x1080, 1366x768, 1024x768, one width below 900) | Status |
|---|---|---|
| F1 | Incoming change: edit on device B; the open project on device A updates its list, counts, Dashboard and the selected task without switching project. With unsaved edits on A, the edit stays and the banner shows | not run |
| F2 | Due date shows the full day at every size; time can be added, changed and removed; clearing the date clears the time; the time row is disabled with the reason when signed in | not run |
| F3 | Details: project above the title; long names ellipsize; save bar pinned | not run |
| F4 | Reminder dialog: presets show the right date and time; custom; past error; Cancel; a real Windows notification fires | not run |
| F5 | Add subtask: current task preselected; another parent of the same project can be chosen | not run |
| F6 | Search on its own row; wrap at narrow widths; **Ctrl+F with the real keyboard** from the list, sidebar, a filter chip and the Dashboard; focus ring visible on every control in both themes; panels resize by mouse and keyboard; overlay at 1024 unchanged | not run |
| F7 | First launch opens maximized with the normal title bar; resize, close, reopen restores; unplug a monitor or change resolution: the window opens reachable (this is the first check of the native code, which CI only compiles) | not run |
| F8 | About shows the version, short commit and build type, and they equal `BUILD-INFO.json` in the ZIP; the DEVELOPMENT TEST build is marked | not run |
| F9 | The 18 regenerated goldens look right | regenerated on the Windows runner (`regenerate-goldens` run 43864098418, head `011da25`) and committed; still needs the owner's look |

## Next-build checks (1.1.0+2; all **not run**; the 15 rows above and F1 to F9 stay as stated)
Run on the CI-built portable ZIPs: the local-only release build and the sign-in **DEVELOPMENT TEST** build. Dark and Light; 100 % and 150 %; 1920x1080, 1366x768, 1024x768 and one width below 900. Rows F10 to F14 need the hosted due-time migration (`docs/operations/due-time-hosted-migration.md`, not applied, owner approval) and the existing TEST account.

| # | Check | Status |
|---|---|---|
| F10 | About shows 1.1.0+2, the short commit of the artifact's `BUILD-INFO.json` and the right build type: **Release build / Off** for the local ZIP, **DEVELOPMENT TEST / On** for the sync ZIP; the sync build shows the sync card and Sign in, the local build never does | not run |
| F11 | Sign in (TEST account); the account workspace is empty or its own; nothing local was uploaded; *Import local data* lists projects first, warns about due times while the server cannot store them, and nothing happens until confirmed | not run |
| F12 | **Stale UI:** on device B edit and add tasks; on device A (project open, a task selected) the list, details, sidebar counts and Dashboard update without switching project; with unsaved edits on A they stay and the banner shows | not run |
| F13 | **Due time synchronized** (after the hosted migration): set, change, clear, move the date, clear the date on A; B shows the same; date-only tasks stay date-only; two-device conflict on the time resolves; an older build changing the date clears the time | not run |
| F14 | Time row disabled with the reason on a server without the migration, enabled after it (no restart needed beyond the next sync) | not run |
| F15 | New subtask dialog: the parent card is clearly visible in both themes, the current task preselected, another parent choosable | not run |
| F16 | Task tree: parents show direct children at start, deeper levels stay closed; collapse and expand by mouse and arrow keys; a collapse survives a refresh, sort, search and filter | not run |
| F17 | Related subtask in the details panel: nested levels open to the task, it is selected, in view and focused; with a search or status filter active nothing is cleared and the notice offers explicit actions; with unsaved edits the gate asks | not run |
| F18 | New task dialog: Project above Title, Tab order Project, Title, Cancel, Create, Enter creates | not run |
| F19 | Real-keyboard **Ctrl+F** from the list, a sidebar item and the Dashboard | not run |
| F20 | Goldens regenerated on Windows for this layout (default expansion changes the demo-data screens) | not run |


## Exit and UI refinement checks (all **not run**; nothing above is marked passed by them)
Automated evidence only (CI run 45203271612, head `8a1325e`): the Windows tests, build and shell smoke passed, including tray Exit ending the process when nothing is unsaved. That is not a GUI observation of the rows below.
Run on the CI-built portable ZIPs (default and sync DEVELOPMENT TEST build), Dark and Light, 100 % and 150 %. Details: implementation record section 10.

| # | Check | Status |
|---|---|---|
| F21 | **Exit with unsaved edits, title-bar X.** Open a task, change Notes, click X: the dialog Save / Discard / Cancel appears. Cancel keeps the app and the text; Discard closes without saving (reopen: text gone); Save closes and the text is there after reopening. Repeat with title, status, priority, due date | not run |
| F22 | **Exit with unsaved edits, tray Exit.** Same, with the tray menu Exit (also with the window minimized to the tray: the window comes forward with the dialog; no second dialog on a second Exit; the app stays open while the dialog waits for longer than 4 s). Make Save fail (for example a read-only data folder) and confirm the draft stays and the app does not exit | not run |
| F23 | Clean app: X and tray Exit close at once; minimize to the tray keeps the draft; restoring shows it; reminders still fire | not run |
| F24 | Panel widths: drag and keyboard-resize both panels, close and restart: widths restored; double-click a divider, restart: defaults; a smaller window still fits | not run |
| F25 | Hidden-task notice: with a search active select a hidden related subtask: the banner is easy to see in both themes; Clear search clears only the search and reveals the task | not run |
| F26 | New task project picker and New subtask parent picker at 150 %: the list is short and scrolls, themed, keyboard and focus work | not run |
| F27 | Search a word that only occurs in a task's Notes: the row shows "In notes: ..." with the word emphasised; a task with the word in its title shows none | not run |
| F28 | Narrow widths at 150 %: the reminder strip keeps the task name; long project names have a tooltip; the sync card title is readable, the action sits below when needed | not run |
| F29 | Second launch while Nexora is behind another application: the window comes to the front. If Windows only flashes the taskbar button, note it (known limitation, behaviour as before) | not run |
| F30 | The four regenerated alert-bar goldens (the sync card action now sits under the title when both do not fit); the other 18 are byte-identical to before | regenerated on the Windows runner (`regenerate-goldens` run 45202258519, head `41b33c9`) and committed; still needs the owner's look |

## Hosted due-time migration and hosted checks (2026-11-16, DEV/TEST project `uicccaawtjvqggeufbez`)
Owner-authorized: the exact migration file below, and the hosted HTTP/JWT and two-device checks with the test account the owner supplied (no service-role key; test data only).

| Check | Source | Command / run | Result | Evidence |
|---|---|---|---|---|
| Migration applied | `supabase/migrations/20261116100000_nexora_due_time.sql`, SHA-256 `71ebd1de87cb5d95bca0fddf99b2a8401b26d6946f8ca913a4e8d9570c59263e`, content applied unchanged | Supabase `apply_migration` (recorded in the hosted history as `20261116143627 nexora_due_time`) | PASS | read-only follow-up below |
| Schema, RLS, grants | head `8fe2d59` | select-only queries | PASS | `tasks.due_time time NULL`; check `tasks_due_time_needs_date`; RLS on; `authenticated` still has SELECT only on `tasks`; internal functions have no `authenticated` execute (only `register_device`, as before); existing 1,041 tasks have no time |
| Register answers `features: ["due_time"]` | hosted | HTTP/JWT (GoTrue sign-in, PostgREST RPC) | PASS | |
| Two-device push/pull, `field_versions.due_time`, conflict on `due_time`, `resolved_merged`, `blocked_by_conflict` | hosted | HTTP/JWT, two registered devices | PASS | 24 of 24 assertions |
| Date+time together; older-client date change clears the time; clearing the time keeps the date; date-only stays date-only | hosted | same | PASS | |
| Invalid times (`17:30:15`, `24:00`, `7pm`, `25:00`), time without a date | hosted | same | PASS (rejected) | |
| Direct PATCH/INSERT on `tasks` refused; anon key and no-JWT RPC refused; private function not exposed | hosted | same | PASS | |
| Signed-in app turns synchronized due time on after the register answer; local-to-account import of times | client code | covered by the 17 local two-device e2e tests and runtime tests only | NOT TESTED against hosted with the real app | needs the Windows GUI |

Hosted test data written (all under the test account): one project `phase5-duetime-check` with 3 tasks, and 4 devices labelled `phase5-duetime-check` (two came from a script slip). Nothing existing was changed or deleted; one pre-existing open conflict is untouched.

Windows DEVELOPMENT TEST build: workflow run `43884009708` (manual dispatch on the branch head, no merge commit), source `8fe2d592ed76d97d505ec0140870f21b87d0c53e`, artifact `nexora-windows-sync-DEVELOPMENT-TEST` (id 14232624117, 13,928,779 bytes, SHA-256 `f6a2cd7738f3e457c5ff29041028c7328e0c0f0dc5f6df6264e96cbd3849a03f`). CI: build, sign-in self-test, shell smoke (single instance, tray), ZIP smoke launch PASS. About screen on a real Windows machine vs `BUILD-INFO.json`: NOT TESTED. F1 to F20 remain NOT TESTED.
