# ADR 0004: Optional time of day on a due date, and where it stops

Status: implemented for the **local-only workspace** on `feature/phase-5-ui-ux`. **Synchronizing a time needs a hosted schema change that has not been made and is not part of this work.** The owner decides (section 6). Register: `docs/coordination/status-register.md`.

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

## 4. Storage (implemented)
Local schema **version 5** adds one table, `task_due_times(task_id PRIMARY KEY, due_time TEXT CHECK 'HH:MM')`, beside `tasks` and with no foreign key (a pull can never delete or rewrite it). `tasks`, the outbox, pull, conflict and digest code are unchanged. A time-only edit writes no outbox operation and does not touch the task's version. A create or update patch never contains the time (tests in `due_time_sqlite_test.dart`). A date-only task has no row. Migration 5 is forward-only and additive (no backup needed, like version 4). **An older build refuses a version 5 file and leaves it untouched** ("newer than supported"), so an old client can never ignore a time and then change the date under it. Existing version 4 files open at 5 with every task unchanged (tested).

## 5. What works where
| Workspace | Time of day |
|---|---|
| Local-only (default build; sync-build before sign-in) | Works fully: set, change, remove, sort, display, restart. Device-local file. |
| Signed in (account workspace) | **Off, visibly.** The time row is disabled and says "Time of day is not synchronized yet, so it is off while signed in." The workspace refuses a time even if asked (`dueTimeSupported`). Date-only deadlines work as before. |
| Import local to account | Tasks keep their date; **the time is not carried** (it has nowhere to go). Document this to the owner; the import preview does not yet warn about it. |

This is the deliberate, visible alternative to a time that looks saved and is not: a synchronized workspace never holds a time that another device would not see.

## 6. The hosted change that would unblock synchronization (NOT applied, NOT in `supabase/migrations`)
Needs a separate owner decision and the hosted-deployment gate (`docs/operations/s1-hosted-deployment-gate.md`). Proposed shape, for review only:

1. Hosted: `alter table public.tasks add column due_time time without time zone null;` plus a guard rule that `due_time is null or due_date is not null`, and add `due_time` to the tracked/allowed fields (`field_versions`, allowed patch keys, type `["string", true]`, authoritative row, pull select). A trigger that sets `due_time = null` when a patch changes `due_date` without sending `due_time` protects against an old client changing the date under a time.
2. Wire contract (`s2-wire-contract.md`) and data contract (`data-contract.md`): new field `due_time` (`HH:MM`, nullable). Client: `entity_patch.dart` field lists, pull applier, snapshot digest, conflict mirror (`conflicts.dart` field names and labels), local schema (move the time into `tasks` or keep the table and sync it).
3. Compatibility: an old client ignores `due_time` (it is a new column in the authoritative row) and shows the task date-only. If an old client edits the due date, the trigger removes the time, so a stale time can never survive a date change. If an old client moves the date only, the other device's time is cleared, which is the safe outcome.
4. **Acceptance criteria blocked until then:** time of day synchronized between two devices; time in conflict resolution; time on import into an account; time in the signed-in workspace (the row stays disabled until `dueTimeSupported` is switched on for it).

Independent work (done): everything in sections 3 to 5.

## 7. Rejected alternatives
- Encode the time inside `due_date` (`date` truncates it silently; breaks old clients and the `GLOB`).
- Store the time in `notes` or in a title suffix (corrupts user data).
- Keep a device-local time in a signed-in workspace without saying so (the value would not reach other devices and would go stale when they change the date).
- Store UTC instants (a date-only value would need a time zone, and a date could shift across zones).

## 8. Consequences
- Version 5 of the local file; builds older than this refuse it.
- Two existing tests changed (the schema version expectation in `reminder_store_test.dart`: 4 to 5, and the stepped-back v3 file also drops the new table).
- The owner's remaining decision: approve the hosted change in section 6, or keep time-of-day local-only.
