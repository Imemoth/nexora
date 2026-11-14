# Change request CR-2A-001: Phase 2A SQLite changes required for synchronization

| | |
|---|---|
| To | Owner of `feature/phase-2a-sqlite` |
| From | Phase 2B/3 server stream (`claude/affectionate-turing-unzmd2`) |
| Reviewed state | `origin/feature/phase-2a-sqlite` @ `9f71c15` (plan, `migrations.dart`, `sqlite_task_repository.dart`) |
| Server contract | `docs/architecture/data-contract.md` ("Phase 3 additions"), `docs/architecture/decisions/0002-sync-protocol.md`, `docs/superpowers/plans/2026-11-12-nexora-phase-3-sync.md` |
| Status | **Request, answered in part (see "Phase 2A response").** Nothing on the Phase 2A branch was changed or will be changed by the server stream. |
| Blocks | Phase 3 slices S5 (outbox v2) and S6 (sync engine). Does **not** block Phase 2A's own acceptance (SAVE-PERSIST-01). |

## Phase 2A response (read 2026-11-12 at `c970d61`, PR #13 Draft, CI run 43219760973 success)
Source: `docs/architecture/phase-2a-data-contract-alignment.md` on `feature/phase-2a-sqlite`.

| ID | Phase 2A status | Still open |
|---|---|---|
| REQ-1 | **Implemented** (task update, project update, soft delete never change `version`) | none |
| REQ-2 | Not implemented; deferred to Phase 3 S5 | owner approval of outbox v2 |
| REQ-3 | Encoded only: creates and edits after a pending create carry base 0; no mapping to server types | **Patch-only update payloads are not acknowledged**: the payload is still the whole row. Required before S6 |
| REQ-4 | Partial: `meta.owner_id` created once | name (`owner_id` vs `user_id`); `sync_state`, conflict mirror in S5 |
| REQ-5 | Transaction half implemented | pull rule is Phase 3 |
| REQ-6 | Deferred (no delete UI; single-row soft delete) | Phase 3 |
| REQ-7 | **Implemented** (`''` notes, vocabulary, title refused above 200) | table CHECK still 500 (their D-3) |
| REQ-8 | Generator is UUIDv4; validation on push is Phase 3 | Phase 3 |

Owner decisions they raised: outbox v2 approval; stored version of a pending create (D-1); title CHECK (D-3); owner binding name.

## 0. Critical requirement (REQ-1)
**A local edit must never change `version`.** `version` is owned by the server. Locally it means "the last server version I know of", and only a pull or an acknowledgement may change it.

### Evidence in the current code (`lib/features/tasks/data/sqlite_task_repository.dart`)
| Lines | Current behaviour |
|---|---|
| 103-113 (`softDeleteTask`) | writes `version = version + 1`, enqueues `baseVersion: version` |
| 188-218 (`_upsertTask`) | writes `version + 1` (line 209), enqueues `baseVersion: version` |
| 271-287 (`_upsertProject`) | writes `version + 1` (line 275), enqueues `baseVersion: version` |

### Why this breaks synchronization
1. Device A edits a task twice offline. Locally `version` goes 1 → 2 → 3 while the server is still at 1.
2. Device B edits the same task once and syncs. The server is at 2.
3. When A pulls, it sees server `version 2` against its own `3`. It cannot tell its own unsynced edits from B's change, so a rule such as "apply the server row if its version is higher" silently discards B's edit.
4. The server checks `base_version` per field (`field_versions[f] > base_version`). A locally inflated `base_version` can hide a real conflict or invent a false one.

### Required behaviour
- `tasks.version` and `projects.version` change only in two places: applying a pulled server row, and recording an ack (`applied_version` from the server).
- A local edit leaves `version` unchanged and writes an outbox row whose `base_version` equals the stored `version` (0 for a create).
- `updated_at` may still be set locally for display; the server value replaces it on the next pull.

### Acceptance tests (Phase 2A side)
- `local_edit_does_not_change_version`: save a synced task (version 5) twice; `version` stays 5; two outbox rows both carry `base_version = 5`.
- `soft_delete_does_not_change_version`.
- `pending_create_ops_carry_base_version_0`: the create op, and any edit made before the create is acknowledged, carry `base_version = 0`. How the row stores `version` meanwhile is open (Phase 2A D-1: stored `0` with the CHECK relaxed in migration v2, or stored `1` with the base derived from the outbox); both satisfy this test.
- `ack_sets_version_from_server`.

## 1. Requirements REQ-1 to REQ-8
| ID | Requirement | Current state (evidence) | Acceptance tests |
|---|---|---|---|
| **REQ-1** | Server-owned local `version` (section 0) | version incremented locally at the lines above | the four tests in section 0 |
| **REQ-2** | Outbox v2 as a forward migration, or an edit of v1 if v1 has not shipped to any user database (Phase 2A owner decides; never edit a shipped migration). Columns: `seq INTEGER PRIMARY KEY AUTOINCREMENT`, states `pending, in_flight, applied, conflict, rejected`, `request_id`, `sent_at`, `server_result_json`, `depends_on_seq`. Relax `version > 0` to `version >= 0` | `operation_id` PK, states `pending/sent/acked/failed`, no order column, `version > 0` (`migrations.dart` v1) | `seq_order_survives_restart`, `crash_in_flight_returns_to_pending`, `migration_v1_to_v2_keeps_pending_ops` |
| **REQ-3** | Operation mapping and **field-level patch payload**: `upsert` with `base_version = 0` maps to server `create`, otherwise `update`; `delete` stays `delete`. The payload of an update contains **only the fields that changed** (diff against the stored row), never the whole row | `_taskPayload(task)` and the project payload send every field (lines 178, 219, 263-286) | `update_payload_contains_only_changed_fields`, `create_payload_contains_all_required_fields`, `unchanged_save_writes_no_outbox_row` (already true, keep) |
| **REQ-4** | New local tables: `sync_state` (singleton row: `user_id`, `device_id`, `cursor`, `state`) and `sync_conflicts_local` (mirror of server conflicts). `meta.user_id` binds the database to one user; the existing `owner_id` constant must come from it | owner id is a constructor value (`_ownerId`); no cursor, no device id, no conflicts | `db_bound_to_single_user`, `device_id_created_once_and_persisted`, `second_user_open_is_refused` |
| **REQ-5** | A domain write and its outbox row stay in one SQLite transaction (already so). A pull must never overwrite a field that has a pending outbox op; the pulled row is stored but the local pending field keeps its value until push resolves it | `_transaction` wraps both (line 98 onward); no pull path yet | `domain_write_and_outbox_row_atomic` (inject a fault between the two statements), `pull_does_not_overwrite_pending_field` |
| **REQ-6** | Deleting a task or project with descendants writes tombstone ops **leaf-first, then the parent**, in one transaction, in `seq` order. The server never cascades | `softDeleteTask` tombstones one row only (lines 96-117); descendants stay live | `delete_tree_writes_leaf_first_ops`, `delete_parent_does_not_leave_live_children` | **Held until the S3 gate (2026-11-12):** chain atomicity is not provided by S2; see `docs/coordination/phase-3-s5-outbox-v2.md` section 9.
| **REQ-7** | Align stored values with the contract: `notes` stored as `''` (server column is `NOT NULL DEFAULT ''`); status `review` and `archived` and priority `none` are valid server values now; title max 200 | `_notesColumn` maps `''` to NULL (line 433); plan section 2.1 still says the server rejects `review`/`archived`/`none` and has nullable notes (stale since Phase 2B) | `notes_round_trip_as_empty_string`, `status_and_priority_vocabulary_matches_contract` |
| **REQ-8** | Ids are UUIDv4, lowercase, hyphenated, validated on write | `RandomIdGenerator`; no validation at the repository boundary | `rejects_malformed_uuid`, `ids_are_lowercase` |

## 2. Further consequences the Phase 2A owner should know about
- **Follow-up operations on the same entity.** After op 1 is acknowledged, the server version moves on. The sync engine (S6) rewrites the `base_version` of the next pending op for that entity from the ack just before sending. The outbox therefore needs `depends_on_seq` (or an equivalent per-entity ordering) so the engine knows which op is next for an entity. The repository itself keeps writing `base_version = stored version`. **Superseded 2026-11-12 (S5 reconciliation):** rewriting the base from the previous acknowledgement is unsafe in general (it can suppress a real conflict); the dependency-adjusted rule R in `docs/coordination/phase-3-s5-outbox-v2.md` section 2 applies.
- **`sort_order` type.** Local `INTEGER`, server `numeric`. Integers are a valid subset; keep integers locally.
- **Timestamps.** `created_at` and `updated_at` are server-owned once synced. Local values are placeholders until the first pull.
- **Local seed data** (`demo_seeded`) must not enter the outbox (already so per plan 5.3) and must not be pushed.

## 3. Proposed schema (proposal text only; not applied anywhere)
> **Corrected 2026-11-12 (owner direction, see `docs/coordination/phase-3-s5-outbox-v2.md` section 3a):** the copy order is the verified v1 `rowid` order, never `created_at_utc`; and v1 rows in the ambiguous states `sent` and `failed` are preserved without automatic replay, version reset or loss, so the state mapping below must **not** be executed as written. The SQL is kept as a schema sketch only.
```sql
-- outbox v2 (forward migration, version 2)
ALTER TABLE sync_outbox RENAME TO sync_outbox_v1;
CREATE TABLE sync_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  operation_id TEXT NOT NULL UNIQUE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('project','task')),
  entity_id TEXT NOT NULL,
  operation_type TEXT NOT NULL CHECK (operation_type IN ('upsert','delete')),
  base_version INTEGER NOT NULL CHECK (base_version >= 0),
  payload_json TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending','in_flight','applied','conflict','rejected')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error TEXT NULL,
  request_id TEXT NULL,
  sent_at TEXT NULL,
  server_result_json TEXT NULL,
  depends_on_seq INTEGER NULL REFERENCES sync_outbox (seq)
);
INSERT INTO sync_outbox (operation_id, entity_type, entity_id, operation_type, base_version,
  payload_json, created_at_utc, state, attempts, last_error)
SELECT operation_id, entity_type, entity_id, operation_type, base_version, payload_json,
  created_at_utc, CASE state WHEN 'acked' THEN 'applied' WHEN 'pending' THEN 'pending' END,   -- sent and failed: preserved, mechanism open (S5-Q1)
  attempts, last_error FROM sync_outbox_v1 WHERE state IN ('acked', 'pending') ORDER BY rowid;
CREATE TABLE sync_state (
  singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
  user_id TEXT NOT NULL, device_id TEXT NOT NULL,
  cursor INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL DEFAULT 'idle'
);
CREATE TABLE sync_conflicts_local (
  id TEXT PRIMARY KEY, operation_id TEXT NOT NULL, entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL, kind TEXT NOT NULL, fields_json TEXT NOT NULL,
  server_value_json TEXT NOT NULL, client_value_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open', created_at_utc TEXT NOT NULL
);
```
(The final column set is the Phase 2A owner's to decide; the contract only requires the behaviours in section 1.)

## 4. Questions for the Phase 2A owner
1. Has migration v1 shipped to any user database? If not, fold REQ-2 into v1; if yes, add v2.
2. Is `version = 0` for never-synced rows acceptable, or should a separate `synced INTEGER` flag be used? (Contract works with either; `base_version = 0` must mean "create".)
3. Which slice of Phase 2A should carry REQ-1 and REQ-3 (they change repository behaviour and tests)?

## 5. Sequence and compatibility
- No server dependency: every item can be implemented and tested against SQLite alone.
- Server side is ready in design; the server schema and RPCs are not applied or active, and synchronization stays disabled until separate owner approval.
- Phase 2A's own acceptance (SAVE-PERSIST-01) is unaffected; REQ items can land before or after it.

## 6. Out of scope for Phase 2A
Supabase package or client, network, authentication, the sync engine, conflict UI, background sync. Phase 3 slices S5-S7 own those after separate approval.

## 7. Sign-off
| Item | Phase 2A owner decision | Date |
|---|---|---|
| REQ-1 server-owned version | _accept / reject / counter_ | |
| REQ-2 outbox v2 | | |
| REQ-3 mapping and patch payload | | |
| REQ-4 sync_state, user binding | | |
| REQ-5 pending-field protection | | |
| REQ-6 leaf-first tombstones | | |
| REQ-7 vocabulary alignment | | |
| REQ-8 id validation | | |
| Questions in section 4 answered | | |
