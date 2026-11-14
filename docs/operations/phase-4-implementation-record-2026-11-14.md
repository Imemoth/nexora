# Phase 4: Windows reminders, system tray and notifications (implementation record)

Status of the phase and its gates: `docs/coordination/status-register.md`. Baseline: `main` at `9499da6` (Phase 3 merged). Work happened on the existing development branch after a non-rewriting fast-forward from `main`. No hosted Supabase change was made or is needed.

## 1. Decisions made in this package
| ID | Decision | Reason |
|---|---|---|
| D-RM | **Reminders are device-local.** They live in the SQLite file of the active workspace (so they follow the account on this device) and are **never synchronized**. The details panel says so: "Reminders are stored on this device only. They are not synchronized and do not appear on your other devices." | Synchronizing needs a hosted schema change and a conflict model for a per-device notification state; the owner asked to avoid hosted writes. A synchronized variant remains possible later (see section 7). |
| D-RW | A reminder time is a **local wall-clock time** (like an alarm clock), converted to an instant only when it is evaluated. | A change of time zone or a daylight-saving switch moves the instant, not the time the user chose. |
| D-RX | The window's close button **exits** the app; **minimize** goes to the tray. Tray menu: Open Nexora, Exit. | Standard behaviour; Exit is explicit and always terminates. |
| D-RN | Native notifications are Windows shell notifications (tray balloons, shown as toasts on Windows 10/11) from the runner itself. **No new Dart or native package.** | No dependency approval needed; tray and notification share one icon. |

## 2. Reminder model and rules
- Table `task_reminders` (local schema version 4, additive, one transaction, no backup needed, no foreign key so a pull can never delete a reminder): `task_id`, `remind_at_local` (`YYYY-MM-DDTHH:MM`), `state` (`scheduled`, `notified`, `acknowledged`), `snooze_until_utc`, `notified_at_utc`, `missed`, `updated_at_utc`. Code: `lib/features/tasks/data/schema_v4.dart`, `reminder_store.dart`.
- Effective due instant: `snooze_until_utc` when set, otherwise the wall time resolved in the current system zone. A time inside the hour skipped by spring-forward resolves to the same offset after the gap (02:30 fires at 03:30); a repeated time on fall-back fires once, at its first occurrence.
- **No duplicates after a restart:** a due reminder is claimed with one guarded `UPDATE ... WHERE state='scheduled' AND remind_at_local=? AND snooze_until_utc IS ?`, committed **before** the notification is shown. Two services or two ticks can never both win.
- **Missed reminders:** the service evaluates at start-up and every 15 seconds (so resume from sleep, clock changes and DST switches are picked up). A reminder shown later than 2 minutes after its due time is marked missed and labelled so; more than 3 due at once get one summary notification.
- **Never silently lost:** a notification that fails or is suppressed leaves the reminder in `notified`, which keeps it in the in-app reminder list (banner above the task list) until the user acknowledges it. That list is also the fallback when native notifications are unavailable.
- Completing, archiving or deleting a task acknowledges its reminder silently (the task table is read directly, never the possibly not-yet-loaded workspace).
- Cancel (remove), reschedule (replaces; a fired reminder becomes pending again), acknowledge (Done), snooze 10 minutes, 1 hour, tomorrow 09:00. A time in the past is refused.
- Code: `lib/features/tasks/domain/reminder.dart`, `application/reminder_service.dart`; UI `presentation/reminder_field.dart` (details panel, applies at once, not part of the task's Save/Revert draft), `reminder_banner.dart`, strings in `strings/reminder_strings.dart`.

## 3. Windows shell integration (native)
`windows/runner/desktop_integration.{h,cpp}` (compiled into the existing runner) and `lib/platform/desktop_integration.dart` (method channel `nexora/desktop`).
- **Tray:** one icon per process (`NIM_ADD` with a fixed id; re-added after an Explorer restart). Left click or double click restores; right click opens the menu (Open Nexora, Exit).
- **Single instance:** a per-session mutex; a second launch posts a registered activation message to the running instance and exits, so there is never a second window or tray icon. (Development self-test runs skip this check.)
- **Minimize to tray:** minimizing hides the window; the Dart event loop, the reminder timer and the sync scheduler keep running.
- **Notifications:** queued one at a time through the tray icon; a click restores the window and sends `notificationClicked(taskId)`; Dart selects the task (clears the search, opens its project, expands ancestors; with unsaved edits only the selection is requested so the unsaved-change gate decides).
- **Exit:** the tray menu asks Dart to flush and dispose the runtime (bounded to 3 s), then Dart calls `quit`; if Dart does not answer within 4 s the native side ends the process anyway.
- Notifications are not promised after the application has fully exited.

## 4. Integration and data safety
- Authentication, per-account SQLite files and S6 synchronization are unchanged. The reminder service is created per opened workspace by the runtime, so reminders are isolated like the rest of the account database and are absent from the outbox and the server (tested).
- Migration 4 only creates a table; older files migrate in place (tested from versions 1 and 3); a file from a newer app version is still refused.
- The default build keeps `NEXORA_SYNC` off; reminders work in both builds, offline, with no network.

## 4a. Acceptance and evidence
- **Owner manual Windows acceptance (2026-11-14): all six checks passed:** reminder creation and notification delivery; minimize to system tray; notification click opens the correct task; snooze, acknowledge and reschedule; reminder persistence without duplicate notifications; single-instance behaviour. Phase 4 is accepted for the current TEST environment; the device-local model (D-RM) stays for V1.
- **CI on the code head `914435c`:** Windows `CI` 43620789345 (includes the shell smoke and the packaged-app smoke); sync-enabled DEVELOPMENT TEST build 43621629032; PostgreSQL 17 `supabase-tests` 43621631547; `http-integration` 43621634472; `e2e-sync` 43621637048; `docs-check` 43621640442. All succeeded.
- **Defect found by CI and fixed before acceptance:** the first Windows build compiled but the packaged app never opened its database, because `main()` created the method channel before the Flutter binding existed. The channel constructor now initializes the binding; regression test `test/platform/desktop_start_test.dart` fails without the fix.
- Build artifact: `nexora-windows-sync-DEVELOPMENT-TEST` of run 43621629032 (ZIP, `SHA256SUMS.txt` with the commit, README, shell-smoke log).

## 4b. Integration review (diff against `main` `9499da6`)
37 files (22 added, 15 modified), all within Phase 4 scope. Checked and found clean: no change to `pubspec.yaml`/`pubspec.lock` (no new dependency), `supabase/` (no hosted or local migration), golden images, or any Phase 3 sync, auth or conflict code beyond passing the reminder service through `SyncRuntime`/`AppHost`. Risks and handling:
| # | Risk | Handling |
|---|---|---|
| 1 | Native runner code (`windows/runner`) is new and only compiled on Windows CI | built and packaged on CI, shell smoke passed, six manual checks passed |
| 2 | Close button exits, so no reminders after a full exit | documented limitation (D-RX) |
| 3 | Local schema moves to version 4; a file migrated by this build is refused by an older build | additive table, tested from versions 1 and 3; the refusal of newer files is intended |
| 4 | The default build now includes the tray and notification code (sync stays off) | reminders and tray work with no network; `NEXORA_SYNC` default unchanged |
| 5 | The shell smoke step is `continue-on-error` in both workflows | passed on the accepted head; can be made blocking after merge if the owner wants |
| 6 | Single-instance mutex is per user session; a stuck process blocks a second launch from showing a window | second launch asks the first to show itself; development self-tests skip the check |

## 5. Tests
`test/features/reminders/` (domain and DST with a fake New York zone, store and migration, service: schedule, fire once, restart, race, missed, acknowledge, snooze, cancel, reschedule, completed task, failing channel, summary, spring-forward, fall-back, periodic tick, per-file isolation), `test/platform/desktop_integration_test.dart` (channel protocol, fallback when the native runner is absent, click and exit events), `test/app/reminder_ui_test.dart` (editor, banner, acknowledge, snooze, click selects the task, tray Exit saves then ends, still ends on hang or failure), `test/runtime/reminder_runtime_test.dart` (per account, restart, never synchronized, offline). Native tray behaviour is exercised on Windows CI by `tool/windows_shell_smoke.ps1` (single instance, minimize to tray, restore, tray Exit) when the runner has an interactive desktop.

## 6. Remaining limitations
- Reminders are per device (D-RM); a reminder set on one device does not appear on another.
- No notification after the application has fully exited, and the close button exits (use minimize to keep reminders running).
- Notification appearance follows Windows settings (Focus assist can hold toasts back); the in-app reminder list always shows what fired.
- The tray icon uses the application icon; Windows 11 may place it in the overflow area.
- Real-desktop behaviour of the tray, toasts and clicks needs owner acceptance on Windows (this build is the vehicle).

## 7. Possible later work (not part of this package)
A synchronized reminder would need a hosted table or column, RLS, RPC changes and a per-device notification state; prepare and test locally first and deploy only with separate authorization.
