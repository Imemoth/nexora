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
