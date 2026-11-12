# Nexora Phase 2A — Local SQLite Persistence (implementation plan)

Status: **historical plan. Implemented and merged into `main` (PR #13); owner Windows acceptance SAVE-PERSIST-01 recorded.** Current status: `docs/coordination/status-register.md`. (Original text: plan for owner review, no implementation started.) Phase 2A builds on the Phase 1 acceptance head (`64d10cb`, PR #12).

Goal: a Windows desktop app that keeps tasks, projects and nested subtasks across full process restarts, using SQLite on the device, with durable Save and an outbox designed for later synchronization. No Supabase writes, no network, no authentication and no live sync are in this slice.

---

## 1. Verified baseline

| Fact | Evidence |
|---|---|
| Phase 1 storage is in memory only; startup rebuilds demo data | `lib/main.dart:10-18`; `lib/features/tasks/application/in_memory_task_repository.dart:45-52` |
| The repository contract has no project save, no delete and no version | `lib/features/tasks/application/task_repository.dart` (three methods: `loadProjects`, `loadTasks`, `saveTask`) |
| The architecture rule forbids SQLite and Supabase packages anywhere in `lib/` | `test/architecture/import_rules_test.dart` (`_forbiddenEverywhere`) |
| The domain `Task` has no timestamps, owner, version or soft-delete fields | `lib/features/tasks/domain/task.dart:6-31` |
| The domain `Project` has no owner, description, colour, archive flag or version | `lib/features/tasks/domain/project.dart:2-8` |
| The Supabase project has `profiles`, `projects`, `tasks`, `project_members`, all with RLS enabled and zero rows | read-only `list_tables` (verbose) on `public`, and `list_migrations` (one migration: `20261112111349 nexora_initial_domain_schema`) |
| No approved detailed autosave design exists in the repository | Only `specs/…v1-design.md` line 15 and `docs/architecture/decisions/0001…md` line 10 mention autosave. The Phase 2 plan that the Phase 0 plan references (`2026-11-11-nexora-phase-2-offline-domain.md`) is **not in the repository** |

## 2. Shared data contract: comparison and conflicts

The live Supabase schema (`public.tasks`, `public.projects`) is the shared contract the parallel Supabase session is building. The V1 specification's candidate model (`workspaces`, `workspace_members`, `task_notes`, and so on) is older. The owner's brief says the live schema is the reference. The table below lists every disagreement.

### 2.1 `tasks`

| Concept | Dart Phase 1 model | Supabase `public.tasks` (live) | Conflict | Smallest compatible correction |
|---|---|---|---|---|
| Identity | `String id` (UUID v4 from `RandomIdGenerator`) | `uuid`, default `gen_random_uuid()` | None (format matches) | Validate UUID format on the way in |
| Project | `projectId` | `project_id uuid` | None | None |
| Parent | `parentId` | `parent_id uuid`, FK `(parent_id, project_id) → tasks(id, project_id)` | None (same-project rule matches) | None |
| Owner | absent | `owner_id uuid NOT NULL` (FK to projects `(project_id, owner_id)`) | **Missing in Dart** | Add `ownerId` to the local model, set to the local user id (see decision D4) |
| Title | `String`, max 200 | `text`, 1–500 characters | Dart is stricter, so compatible | Keep max 200 locally; the server accepts more |
| Notes | `String notes` | `notes text NULL` | Dart uses `''` for empty, schema uses `NULL` | Store `NULL` for empty locally; map `''` ↔ `NULL` |
| Status | `open, inProgress, review, done, archived` | `open, in_progress, ready_for_review, done` | **Conflict**: Dart has `review` (≈ `ready_for_review`) and `archived`; the schema has no `archived` | Decision D2 |
| Priority | `none, low, medium, high` | `low, medium, high`, default `medium` | **Conflict**: Dart `none` has no server value | Decision D3 |
| Due date | `CalendarDate` (date-only) | `date NULL` | None (both date-only) | Store `YYYY-MM-DD` text locally |
| Position | `int position` | `sort_order numeric`, default 0 | Type differs, meaning matches | Store integer locally; map to `sort_order` |
| Completion time | absent | `completed_at timestamptz NULL` | Missing in Dart | Add `completedAt` (UTC), set when status becomes `done` |
| Version | absent | `version bigint`, default 1, `> 0` | **Missing in Dart** | Add `version` (integer, starts at 1, +1 per committed update) |
| Soft delete | absent | `deleted_at timestamptz NULL` | **Missing in Dart** | Add `deletedAt` (UTC), never removed physically |
| Timestamps | absent | `created_at`, `updated_at timestamptz` | **Missing in Dart** | Add both (UTC) |

### 2.2 `projects`

| Concept | Dart | Supabase `public.projects` | Conflict | Correction |
|---|---|---|---|---|
| Identity | `String id` | `uuid` | None | None |
| Name | `String name` | `text`, 1–200 characters | None | None |
| Order | `int position` | `sort_order numeric` | Type differs | Map to `sort_order` |
| Owner | absent | `owner_id uuid NOT NULL` | **Missing in Dart** | Add `ownerId` (decision D4) |
| Description, colour, archive flag | absent | `description`, `color`, `is_archived` | Not in Dart | Store as optional local columns, unused in the UI for now |
| Version, soft delete, timestamps | absent | `version`, `deleted_at`, `created_at`, `updated_at` | Missing in Dart | As for tasks |

### 2.3 Other tables

- `project_members` (`project_id`, `user_id`, `role` in `viewer|editor`) has no Dart counterpart. It is needed only for sharing, which is out of scope for Phase 2A. Nothing is stored locally.
- `profiles` is not needed locally in Phase 2A.
- The V1 specification's `workspaces`, `workspace_members`, `task_notes`, `reminders` and `task_events` have no live counterpart. They are not part of this slice.

### 2.4 What the schema also implies for local rules

- `tasks.parent_id` must refer to a task in the same project. The Phase 1 rule already enforces this, so local storage must keep it as a foreign key.
- `tasks.owner_id` must match the project's owner. The local store must enforce this when a task is written.

## 3. Proposed architecture

- **Domain and application** stay pure Dart. They gain only new fields (`ownerId`, `version`, timestamps, `deletedAt`). No storage code enters them.
- **A new infrastructure area** `lib/features/tasks/data/` holds the SQLite implementation of `TaskRepository` and the migrations. This is a deliberate exception to the import rule, so it requires an explicit, reviewed change to `test/architecture/import_rules_test.dart`. The change is limited to: `package:sqlite*` is allowed only under `lib/features/tasks/data/` and `lib/core/storage/`. No other package and no Supabase import is allowed.
- **Presentation** continues to depend only on `TasksNotifier`, `TaskWorkspace` and `AppStrings`. No widget may import the data layer.
- **`InMemoryTaskRepository` stays** for deterministic widget and unit tests and for development scenarios, unchanged.
- **Repository interface extension (proposed):** add `saveProject`, `deleteTask` (soft: sets `deletedAt`), and an explicit `openOrSeed` startup step that is idempotent. `saveTask` keeps its contract: it returns only after the commit.

## 4. Decisions the owner must approve before implementation

| ID | Decision | Options | Recommendation | Why it is needed |
|---|---|---|---|---|
| D1 | SQLite library | (a) `sqlite3` package (Dart FFI, pinned); (b) `drift` (ORM over `sqlite3`, adds code generation); (c) `sqflite` | (a) `sqlite3`, exact-pinned, no code generation. Drift is heavier than this slice needs. `sqflite` has no Windows desktop support, so it is ruled out | Adding a runtime dependency needs approval under the project rules. Windows packaging must be proven in CI: the DLL must be bundled into the portable ZIP, and `tool/package_windows.ps1` must be updated |
| D2 | Status vocabulary | (a) keep Dart statuses and extend the shared schema check in a new Supabase migration (owned by the parallel Supabase session); (b) map `review` → `ready_for_review`, and store `archived` locally only; (c) drop `archived` | (a). A shared schema must not diverge from the local model. Until the Supabase session agrees, archived tasks cannot sync | The live check constraint rejects `archived` and `review` |
| D3 | Priority `none` | (a) change the server default and check to allow `none`; (b) map `none` → `medium` and lose the distinction; (c) keep `none` locally only | (a), agreed with the Supabase session. Phase 1 decision 6 defines `none` as a real value, and changing it is a domain change | The live check allows only `low, medium, high` |
| D4 | Ownership | (a) follow the live schema: `owner_id` on projects and tasks, `project_members` for sharing; (b) follow the V1 specification's `workspace` model | (a). The migration is already applied, and the owner's brief names it as the reference | The spec's `workspaces` model conflicts with the applied schema |
| D5 | Autosave behaviour | (a) none in Phase 2A, Save is manual only; (b) debounced autosave with defined triggers, failure and retry | (a) for this slice. No approved autosave design exists in the repository. Autosave is then a separate, approved slice | Section 1 shows that no approved behaviour exists to implement |
| D6 | Database location | (a) `%APPDATA%\Nexora\nexora.db`; (b) beside `nexora.exe` | (a). The portable ZIP stays immutable, and data survives re-extraction | Determines where the user's data lives |
| D7 | Demo data policy | (a) seed only when the database is new, and record that the seed ran; (b) always seed; (c) reset action | (a). A reset, if wanted, is a separate explicit user action in a later slice | Required by the brief: demo data must not overwrite an existing database |
| D8 | Architecture rule change | approve the narrow exception for `lib/features/tasks/data/` and `lib/core/storage/` | Approve, with the test change reviewed | The current rule forbids every SQLite import in `lib/` |

## 5. Persistence behaviour

### 5.1 Durable Save
- `saveTask` (and project saves) run in a single SQLite transaction and return only after `COMMIT`.
- The workspace already treats a failed save as `saveFailed`, keeps the draft, and keeps selection and pending transitions (see `task_workspace.dart`, `_persistDraft` and `_commitCreate`). Phase 2A keeps that behaviour and only replaces the repository.
- The UI reports success only after the future completes. The existing `Task created` and `Edited, not saved` states remain tied to the workspace, which updates only after the commit returns.

### 5.2 Migrations
- `PRAGMA user_version` holds the schema version. Migrations are ordered and each runs in its own transaction.
- Connection settings: `foreign_keys = ON`, `journal_mode = WAL`, `synchronous = FULL`, `busy_timeout` set.
- A migration that fails rolls back and leaves the database unchanged. The app then shows an actionable error and does not reset or reseed.

### 5.3 Startup
1. Open the database at the configured path (D6), creating it if absent.
2. Run pending migrations.
3. Seed demo data only if the database is new (D7). The seed records a `demo_seeded` marker in the same transaction, so it cannot run twice.
4. Load projects and tasks, then build the workspace.
5. If opening fails, show an error and do not fall back silently to demo data.

### 5.4 Outbox (designed, not synchronized)
Table `sync_outbox`, written in the same transaction as the domain change:

| Column | Purpose |
|---|---|
| `operation_id` (UUID, unique) | Stable identity and idempotency key |
| `entity_type`, `entity_id` | What changed |
| `operation_type` | `upsert` or `delete` |
| `base_version` | The version the edit was based on (sync contract) |
| `payload_json` | The changed fields |
| `created_at_utc` | Local creation time |
| `state` | `pending`, `sent`, `acked`, `failed` |
| `attempts`, `last_error` | Retry state |

No Supabase calls are made in this slice. The outbox only accumulates operations.

## 6. Race conditions

- Manual Save, Discard, task switching and creation already run under the workspace's `_saving` and `_transitioning` guards. Phase 2A keeps those guards unchanged.
- Autosave (D5) is out of this slice. If approved later, it must pass through the same guards.
- Shutdown: the existing exit gate stays in place. A dirty draft still opens the unsaved-change dialog. Nothing is saved on exit without the user's choice, unless autosave is approved.
- Discard never writes. The existing transactional Discard rule is kept.

## 7. Tests

- **Unit tests** (existing): domain and application behaviour unchanged. New fields get round-trip tests.
- **Repository integration tests** against a real temporary SQLite file, using the `sqlite3` library on Windows CI: create and save a task, edit it, nested subtask persistence, multi-level hierarchy reconstruction, project relationships, status and priority, due date preservation, notes preservation, soft deletion, failed-write recovery (a forced failure inside a transaction leaves no partial state), repeated Save idempotency, and migration from version 0.
- **Application restart test**: close the repository, reopen the same file, and check that the workspace loads the same tasks and hierarchy.
- **Widget tests** (existing) continue to use the in-memory repository, so they stay deterministic.
- **Full-process restart acceptance (SAVE-PERSIST-01)**: the Windows app is launched, a task is created and edited, the process is terminated, the app is relaunched, and the data is checked. This needs an executable Windows environment. In CI it can be run as an `integration_test` on the Windows runner, which is an SDK package and needs no new dependency, or as a manual step for the owner.

## 8. SAVE-PERSIST-01 mapping

1. Start Nexora. 2. Create a nested subtask under an existing task. 3. Modify title, status, priority, due date and notes. 4. Save. 5. Navigate away and back. 6. Terminate the process. 7. Restart. 8. Check the task and all saved fields. 9. Check the parent-child relationship. 10. Check counters and hierarchy indicators.

Steps 1–5 and 8–10 are covered by the repository and widget tests above. Steps 6–7 need the full-process test. Acceptance passes only when that test passes on a real Windows process.

## 9. Risks

- **Windows native build**: `sqlite3` needs its native library at runtime. It must be bundled into the portable ZIP and verified in the smoke test. This is the main risk of D1.
- **Schema drift**: the Dart model and the shared schema can diverge again. Decisions D2 to D4 must be closed with the Supabase session before the migration is written.
- **Migration on user data**: a bad migration could lose data. Each migration must be tested on a copy, and failures must leave the database unchanged.
- **Test scope**: the restart test is slow and needs a Windows runner. It must not be skipped to make CI faster.

## 10. Proposed sequence (after approval)

1. RED: repository integration tests against a temporary SQLite file (no implementation).
2. GREEN: `sqlite3` dependency (exact-pinned), migration runner, `SqliteTaskRepository` and project persistence.
3. Startup changes (D6, D7) and the architecture-rule change (D8), each with its own tests.
4. Outbox table and writes in the same transactions.
5. Windows packaging check (DLL bundled), then the full-process restart test on the Windows runner.
6. Full CI on the exact head, then SAVE-PERSIST-01 manual run by the owner.

No step begins until D1 to D8 are approved.
