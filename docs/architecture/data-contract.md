# Shared SQLite / PostgreSQL data contract (Phase 2B)

Status: **FROZEN for Phase 3 (S0), owner decisions 2026-11-12.** Phase 2B migrations are applied on the hosted project. Phase 3 S1 (`20261112130000_nexora_sync_protocol_schema.sql`) was applied to hosted on 2026-11-12 as `20261112151851` (`docs/operations/s1-hosted-deployment-record.md`); synchronization remains disabled. The standalone `guard_row` fix (`20261112125000_nexora_fix_projects_update_guard.sql`) was applied to hosted on 2026-11-12 as `20261112142732` (`docs/operations/f1-hosted-fix-record.md`).
Dart domain source of truth: `lib/features/tasks/domain/`. Not implemented in SQLite by this change.

## Canonical rules and implementation status (2026-11-12)
Legend: **Applied** = on the hosted project. **Implemented** = in code that exists and passed CI (not necessarily merged). **Prepared** = on a development branch, tested, not applied or merged. **Required** = future work, not built.

| # | Canonical rule | Decision | Status |
|---|---|---|---|
| 1 | Ownership is `owner_id`; the revision is `version`. `workspace_id` is deferred (spec deviation) | D1 approved | **Applied** (hosted schema). Phase 2A stores `owner_id` |
| 2 | `version` is server-owned. A local edit never changes it; only a pull or an ack does | D-V approved | **Implemented** in Phase 2A (PR #13, Draft, `c970d61`). Server side **Applied** (guard trigger sets `version`) |
| 3 | Locally pending creates: operations of an entity whose create is unacknowledged carry `base_version = 0`; the sync engine re-bases them from the create's ack before sending | wire rule decided; stored representation open (Phase 2A D-1: stored `0`, or stored `1` with a base derived from the outbox) | Phase 2A derives base `0` from the outbox and stores `1`: **Implemented**. Re-basing: **Required** (S6) |
| 4 | An update operation carries only the fields that changed (field-level patch), never the whole row | D-C approved | Phase 2A sends the full row: **not implemented, Required** before S6 (REQ-3). Server `field_versions`: **Prepared** (S1) |
| 5 | Tombstones are permanent, no undelete. Deleting a parent is explicit leaf-first from the client; the server never cascades | D-T, D-E, D-P approved | Tombstone revert blocked: **Applied**. Leaf-first tombstones and the parent-with-live-children conflict: **Required** (REQ-6, S3). Phase 2A soft-deletes a single row only |
| 6 | Outbox v2 (`seq`, `in_flight`, `request_id`, `sync_state`, local conflict mirror) | deferred to S5 | **Required**, needs owner approval. Not in Phase 2A |
| 7 | Pull cursor safety: per-user advisory lock before `change_seq` | D-L conditional | **Prepared** (S1). Hosted `change_seq` is **not** commit-ordered today, so pull must not be activated until S1 is applied |
| 8 | Push RPCs, idempotency, conflict records, resolution | D-A, D-C, D-O, D-R | Schema objects **Applied** (inert). Device registration and push (S2): **Prepared** on the dev branch (`20261112160000`), PostgreSQL 17 CI green, **not applied to hosted**. Pull (S4) and resolve (S3): **Required**. Synchronization is disabled |

## Identifiers and ownership
- All ids are client-generated UUIDv4 text (lowercase, hyphenated) in SQLite, `uuid` in Postgres. The server accepts the client id on insert; offline-created rows keep their id forever.
- V1 ownership key is `owner_id` (= `auth.users.id`). `project.owner_id` is authoritative; `task.owner_id` must equal its project's owner (composite FK `(project_id, owner_id)`). `id`, `owner_id` and `task.project_id` are immutable.
- **Deviation from approved spec (D1 APPROVED by owner, 2026-11-12):** the spec's candidate model uses `workspace_id`/`revision`. The applied schema uses `owner_id`/`version`. This contract fixes `version` as the wire name for "revision" and defers `workspaces` until sharing is activated (additive later: add `workspace_id`, backfill = owner). Rationale: the Dart domain has no workspace concept and V1 is single-user.

## Fields
| Dart | SQLite (recommended) | Postgres | Notes |
|---|---|---|---|
| `Task.status` open, inProgress, review, done, archived | text | `open`,`in_progress`,`review`,`done`,`archived` | snake_case on the wire; DB previously used `ready_for_review` and lacked `archived` |
| `Task.priority` none, low, medium, high | text | `none`,`low`,`medium`,`high`; default `none` | previously lacked `none`, default `medium` |
| `title` (≤200 UTF-16 units, trimmed, non-empty) | text | `length(btrim(title)) between 1 and 200` | was 500 |
| `notes` | text not null default '' | text not null default '' | was nullable |
| `dueDate` (CalendarDate) | text `YYYY-MM-DD` | `date` | date-only, no time zone |
| `position` (int) | integer | `sort_order numeric` | numeric superset; client may send integers. Ties broken by `id` (client rule unchanged) |
| `parentId` | text null | `parent_id` | same project; no self-parent, no cycles (DB-enforced) |
| — | `version` integer | `version bigint` | see below |
| — | `deleted_at` text UTC ISO-8601 | `timestamptz` | tombstone |
| — | `created_at`,`updated_at` | `timestamptz` | server time, UTC |
| — | `change_seq` integer | `bigint` | server pull cursor |

## Server-controlled fields (client values are ignored/overwritten)
`version` (=1 on insert, +1 on every update), `created_at`, `updated_at`, `change_seq` (global monotonic sequence), `deleted_at` (client sets "deleted", server stamps its own time).
Device clocks never order anything; `client_created_at` on operations is informational.

## Deletion
Soft delete only. Clients have no DELETE privilege. A tombstone cannot be reverted in V1 (no restore). Deleting a parent: the client must tombstone children in the same batch; the server does not cascade silently (Phase 3 rule, see sync design). Tombstones are kept until a compaction policy is approved.

## Conflict detection / concurrency
Optimistic: a client update carries `base_version`; the server applies only if `base_version = current version`. Otherwise same-field overlap creates a `sync_conflicts` row keeping both values; non-overlapping fields may be merged by the Phase 3 RPC. No last-write-wins.

## Idempotency
`sync_operations` primary key `(user_id, operation_id)`; `user_id` is taken from `auth.uid()`, never from the payload. A replay returns the stored `result`; same id with different `request_hash` is rejected.

## Pull
`select ... where owner_id = auth.uid() and change_seq > :cursor order by change_seq limit N`. Cursor = max `change_seq` seen. Commit order of one user's `change_seq` values is guaranteed by the per-user lock (D-L, see "Pull safety" below; **Prepared** in S1, not yet applied). Applying a row is idempotent by `version`.

## Membership
`project_members` has no client privileges and no policy grants task access. Sharing stays inactive.

## Phase 3 additions (S0 freeze)

### Local version semantics (D-V, binding on SQLite)
- Local `version` = the last **server** version known for the row. It changes only from a pull or from an ack, never from a local edit. A local edit does not bump it.
- `base_version` of an operation = that stored value (0 for a create).
- While an entity's create is unacknowledged, its operations carry `base_version = 0`; the sync engine re-bases each from the create's ack before sending. How a never-synced row stores its `version` (`0`, or `1` with a base derived from the outbox) is an open owner decision (Phase 2A D-1); both satisfy the wire rule.
- Update operations contain only the changed fields (field-level patch). A full-row payload would claim every field and cause false conflicts.
- The binding of a local database to its user is stored in `meta` as `owner_id` (Phase 2A) or `user_id` (earlier contract text). The name is an open owner decision (Phase 2A decision 4); the meaning is the same: the Supabase `auth.users.id` the database belongs to.
- A pull never overwrites a field that has a pending outbox operation. The server row is stored, and the conflict is detected when the operation is pushed.

### Server-owned change tracking (D-C)
- `field_versions jsonb` on `projects` and `tasks`: field -> server `version` at which the field last changed. Maintained only by the guard trigger; client values are ignored. Tracked fields: tasks `parent_id,title,notes,status,priority,due_date,completed_at,sort_order,deleted_at`; projects `name,description,color,is_archived,sort_order,deleted_at`.
- An update conflicts only when a patched field has `field_versions[f] > base_version` and the current value differs from the patched value. Equal values merge; different fields merge.
- A conflicting operation applies nothing (D-A). Both values are stored in `sync_conflicts`.

### Operation types
Server: `create | update | delete`. Phase 2A `upsert` maps to `create` when `base_version = 0`, otherwise to `update`. `delete` sets the tombstone.

### Conflict kinds
`field`, `edit_deleted`, `delete_edited`, `parent_deleted`, `parent_has_live_children`, `cycle`, `exists`.

### Deletion (D-P, D-T, D-E)
- The client sends tombstones leaf-first, then the parent. The server never cascades.
- A parent with live children, or a child under a tombstoned parent, is a conflict.
- Tombstones are permanent. An update after a delete is a conflict (`edit_deleted`); resolution is server-wins or recreate-as-copy with a new id.

### Auditable resolution (D-O)
- `sort_order` conflicts may be auto-resolved server-wins only with `resolution_source = 'auto_policy'` and `resolution_policy = 'sort_order_server_wins'`. The conflict row keeps `server_value` and `client_value`; the losing operation stays in `sync_operations` (`patch`, `request_hash`, `result`).
- `sync_operations` is append-only and conflict values are immutable (DB-enforced). No other automatic resolution exists.

### Pull safety (D-L)
- Every write that assigns `change_seq` takes `pg_advisory_xact_lock(hashtextextended(owner_id::text,0))` inside the guard trigger **before** `nextval`, on every path (authenticated, service_role, postgres, future RPCs). The guard triggers are `ENABLE ALWAYS`.
- Pull: `where owner_id = auth.uid() and change_seq > :cursor order by change_seq`.
- A forged owner is rejected before any lock is taken.

### Devices (D-D)
Max 10 active devices per user (revocation frees a slot). `device_id` is not an authentication factor.

### Limits proposed for S2 (to be confirmed there)
<=100 ops per push, patch <=256 KB, RPC statement timeout.
