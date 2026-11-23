# ADR 0004: Optional time of day on a due date, and where it stops

> **Policy:** Nexora is DEVELOPMENT/TEST only; no production exists; the Supabase project is DEV/TEST with mock data. Production-style rollback, release and compatibility parts below are optional guidance, not requirements; hosted writes still need the owner's separate authorization. See [`docs/development-environment-policy.md`](../../development-environment-policy.md).

Status: **implemented** in the client and in a hosted migration that is **prepared and tested locally but NOT applied** (`supabase/migrations/20261116100000_nexora_due_time.sql`; request, sequence, verification and rollback: `docs/operations/due-time-hosted-migration.md`). The first version of this record (local-only time, signed-in time disabled) is superseded where stated below. Register: `docs/coordination/status-register.md`.

## 1. Requirement
A task's due date may carry an optional hour and minute. A date-only deadline stays a genuine date-only value (no fabricated midnight). The time can be removed without removing the date. Existing records and existing clients keep working.

## 2. What was inspected (and what it forces)
| Layer | Finding |
|---|---|
| Hosted `tasks.due_date` | Postgres type **`date`** (`supabase/tests/00_bootstrap_local.sql`, `docs/architecture/data-contract.md` row `dueDate`: "date-only, no time zone"). |
| Wire contract (S2) | `due_date` is a JSON string, nullable; allowed patch keys are fixed (`parent_id, title, notes, status, priority, due_date, completed_at, sort_order`); an unknown key is `rejected: invalid_patch`. `field_versions` tracks the same fields. |
| Local mirror | `tasks.due_date TEXT CHECK (… GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')`; the outbox patch, pull applier, conflict mirror and snapshot digest all read `due_date` as a calendar date. |
| Existing clients | `main` reads `due_date` as `YYYY-MM-DD`. |

Consequence: a time cannot ride inside `due_date` (a `date` column would silently truncate `2026-11-20T17:30` to the date, the next pull would then erase the time on every device, and the local `GLOB` would reject it). A separate synchronized field needs a new hosted column, a wire-contract change (new allowed patch key, `field_versions`, authoritative row) and a local mirror change. Under the standing restriction (no hosted change without separate owner approval) this work **stops at that boundary**.

## 3. Semantics (decided and implemented)
1. **Floating wall-clock time.** A `DueTime` is `HH:MM` on a 24-hour clock with **no time zone and no UTC offset**. It is never converted. "17:30 on 2026-11-20" means 17:30 on the clock of whoever looks at it. This is the same model as the device-local reminders (`LocalWallTime`) and the existing date-only rule.
2. **Date-only is a real state.** `Task.dueTime == null` means "any time that day". Nothing writes a default time; there is no row for it in storage.
3. **A time needs a date.** `Task` refuses a time without a date. Clearing the date clears the time (stated in the UI). Clearing only the time keeps the date. Changing the date keeps the time.
4. **Time zones and daylight saving.** Because the value is never converted, a time-zone change or a daylight-saving transition cannot move it, and a calendar date can never shift to another day. A wall time that does not exist on a spring-forward day (for example 02:30) is stored and shown as written. Nothing is scheduled from a due time: the reminder (a separate, device-local feature with its own DST rules) is independent. Tests: `test/features/tasks/domain/due_time_test.dart`.
5. **Smart views and Overdue stay date-based.** A task due today at 00:01 is in Today and not Overdue until the date passes, exactly as a date-only task. (Time-aware overdue needs "now" in the workspace state; not requested, so not done.)
6. **Sorting.** Due-date sort: date first; on one date tasks with a time come first, earliest first, then date-only tasks (a date-only deadline is due any time that day, so it is the latest); then position, then id. Existing date-only data sorts exactly as before.
7. **Display.** Details: a full-width date row (ISO date, never ellipsized at 900 to 1920 px, both themes, 150 % text) and a time row. List row: `Today · 17:30`, `Fri 20 Nov · 17:30`. A date-only task shows no time.
8. **Due date and reminder stay separate.** The reminder dialog and the due date share nothing.

## 4. Storage
**Local (schema version 6).** `tasks.due_time TEXT NULL` (`HH:MM`, check: a time needs a date, valid 24-hour range) replaces the version 5 side table `task_due_times`; the migration copies existing times (where a date exists) and drops the table. A date-only task keeps NULL. The time travels in the same outbox, pull, snapshot and conflict code as every other task field (`taskUpdatableFields` gained `due_time`), so no parallel mechanism exists. A build older than version 6 refuses a version 6 file untouched.
**Hosted (prepared, not applied).** `public.tasks.due_time time without time zone null` with the check `tasks_due_time_needs_date` (date required, no seconds, below 24:00); tracked in `field_versions`; patch key `due_time` (string or null; the wire form is `HH:MM`, the server answers `HH:MM:SS`, the client normalizes both ways). Existing rows get NULL.

## 5. Synchronization rules (implemented and tested)
1. **Capability.** The server lists `features: ["due_time"]` in the answer to device registration. The client reads it once per engine start and remembers the last answer in the local file (offline use keeps it). The time is used **only** while the server listed it; without it (an unmigrated or rolled-back server, or before the first answer) the time row is disabled with a visible reason, a new time on a synchronized task is refused instead of staying on one device, and dates sync as before.
2. **Date and time travel together.** A patch that changes the date of a task that has a time also carries the (unchanged) time. A patch for a date-only task never mentions a time. Clearing the time sends an explicit null; clearing the date clears both.
3. **Older clients.** If a patch changes the date and does not mention the time, the server clears the stored time in the same update (and in conflict resolution and `recreate_copy`). A stale time cannot survive an incompatible date change. This is a consequence, not an edit, so it raises no conflict. Older clients read rows by name, so the extra key is ignored. The remaining limitation is stated in the hosted request, section 6: an older device that edits a date removes the time.
4. **Conflicts.** `due_time` is its own field with its own field version. Two devices editing the time conflict on `due_time` (label "Due time", values shown as `HH:MM`, a missing time as "No time (date only)"); all strategies work, and a merged pick of the server value is sent in the `HH:MM` wire form. One device moving the date (time kept) while another edits the time merges without a conflict (the time in the date patch equals the stored value, so it is a no-op field); if the time was cleared as the consequence of an older client's date change, a concurrent time edit conflicts on `due_time` against "No time".
5. **Pull.** A pulled row holds date and time as one unit: a pending local edit of either keeps both, so a pulled row can never leave a time without its date. A server row without the key (older server) gives no time. Restoring from the server snapshot treats a missing key as "no time".
6. **Import.** The import preview says how many tasks have a time and, **while the server does not store times, states plainly that they are imported with the date only and the time is not kept**; the import then drops the time and keeps the date. With a migrated server it says times are kept and imports them (and they sync).
7. **Today and Overdue stay date-based**, unchanged. Sorting by due date uses the time as the tie-break (section 3.6).

## 6. What was verified (locally) and what is waiting
Verified on a disposable PostgreSQL 16 and the real client code: 47 SQL assertions (`supabase/tests/due_time_test.sql`), the upgrade and rollback proof (`supabase/tests/verify_due_time_migration.sh`), 17 two-device end-to-end tests (`test/e2e/due_time_sync_test.dart`), local storage and migration tests, runtime capability tests, import tests and UI tests. **Waiting for the owner:** applying the migration to the hosted TEST project (`docs/operations/due-time-hosted-migration.md`). Until then the signed-in build keeps the time off by design, with the reason shown. Not exercised anywhere yet: PostgREST and JWT verification of the new field (the hosted HTTP check in the request covers it).

## 7. Rejected alternatives
- Encode the time inside `due_date` (`date` truncates it silently; breaks old clients and the `GLOB`).
- Store the time in `notes` or in a title suffix (corrupts user data).
- Keep a device-local time in a signed-in workspace without saying so (the value would not reach other devices and would go stale when they change the date).
- Store UTC instants (a date-only value would need a time zone, and a date could shift across zones).

## 8. Consequences
- Version 6 of the local file (version 5 files are migrated in place, times kept); builds older than 6 refuse it.
- Existing tests changed: schema version expectations (`reminder_store_test.dart`), `due_time_sqlite_test.dart` rewritten for the column, the e2e harness registration answer.
- The owner's decision: approve the hosted operation in `docs/operations/due-time-hosted-migration.md`, or keep time of day off while signed in.
