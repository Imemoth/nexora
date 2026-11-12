# Phase 3 S5: SQLite outbox v2 (planning document)

| | |
|---|---|
| Status | **Planning baseline. Not implemented.** SQLite schema v2 does not exist; `lib/` is unchanged by this document. |
| Provenance | **Reconstruction, partly corrected 2026-11-12.** The owner has since said the corrected Session B report is being supplied separately; **as of this reconciliation it has not been received** (not in the repository, any branch, or the instruction), so no line-by-line reconciliation against it has been done and its backup-under-lock design, observed-base versus wire-base semantics, immutable-history and conflict-resolution requirements are **not yet incorporated** (blocker B-16). Section 3a corrects the points the owner stated explicitly. Original provenance note: **Reconstruction.** The owner's message of 2026-11-12 refers to a "corrected S5 specification" accepted as planning baseline. **That text is not in the repository or any branch**, and was not supplied to the implementing session. This document is rebuilt only from sources that are in the repository: CR-2A-001 (`phase-2a-sync-requirements.md`), the Phase 3 plan section 4 and S5/S6, the approved decisions (ADR 0002) and the S2 wire contract. Nothing here is invented policy; every item names its source. **If the corrected specification differs, it wins; send it and this document is reconciled line by line.** |
| Gate | Subject to the compatibility and migration-safety gates in sections 5 and 6 (owner instruction). |
| Depends on | S2 wire contract (`docs/architecture/s2-wire-contract.md`). Independent of S3 and S4 at the SQLite level; S6 (sync engine) needs S5. |

## 1. Scope
In: SQLite migration 2 (outbox v2, `sync_state`, local conflict mirror) and the repository behaviors REQ-1 to REQ-8 that remain open. Out: any network, Supabase client, auth, sync engine (S6), conflict UI, background sync (CR-2A-001 section 6). Synchronization stays disabled (D-F).

## 2. What already exists (verified at `main` 46227c8 and tests)
| CR-2A-001 | State |
|---|---|
| REQ-1 server-owned `version` | Implemented in Phase 2A (local edits never bump `version`) |
| REQ-7 vocabularies, `''` notes, title limit | Implemented |
| REQ-8 UUID validation | Validation on push is server-side; client generator is UUIDv4 |
| REQ-5 transaction half | Implemented and now covered by S5-0 failure injection (`outbox_failure_injection_test.dart`) |
| REQ-2, REQ-3 (payload), REQ-4, REQ-6 | **Open: this slice** |
Frozen baseline: migration v1 (golden tests in S5-0). The v1 outbox has `operation_id` PK, `upsert`/`delete`, `base_version >= 0`, states `pending/sent/acked/failed`, no order column.

## 3. Target behavior (each line has a source)
1. **Migration, not an edit.** Migration v1 is treated as shipped; v2 is added beside it (CR REQ-2 "never edit a shipped migration"; golden tests enforce this).
2. **Outbox v2.** `seq INTEGER PRIMARY KEY AUTOINCREMENT` (total order that survives restart), unique `operation_id`, `entity_type`, `entity_id`, `operation_type` `upsert|delete`, `base_version >= 0`, `payload_json`, `created_at_utc`, `state` in `pending, in_flight, applied, conflict, rejected`, `attempts`, `last_error`, `request_id`, `sent_at`, `server_result_json`, `depends_on_seq` (CR REQ-2, proposal text in CR section 3).
3. **Operation mapping.** `upsert` with `base_version = 0` is sent as `create`; any other `upsert` as `update`; `delete` stays `delete` (CR REQ-3; wire contract section 2).
4. **Patch-only updates.** The `payload_json` of an update holds only the fields that changed against the stored row, never the whole row; a create holds every required field (CR REQ-3; wire contract section 5 allowed keys). Open: Phase 2A still sends whole-row payloads today.
5. **Immutable in-flight payload.** Once an operation is `in_flight` its `operation_id`, `entity_*`, `operation_type`, `base_version` and `payload_json` never change (same `request_hash`; a change under the same id is `operation_id_reuse`).
6. **Follow-up operations on one entity** are ordered by `seq`/`depends_on_seq`; the engine (S6) rewrites the next pending operation's `base_version` from the acknowledgement just before sending (CR section 2). A pending create and its edits carry `base_version = 0` (CR REQ-1 tests).
7. **Acknowledgement** (applied): set `state = applied`, store the result in `server_result_json`, set the row's local `version := applied_version` (the only places `version` changes are a pull and an acknowledgement). `version_before` is recorded with the result.
8. **Conflict mirror.** `sync_conflicts_local` mirrors the wire `conflict` object (wire contract section 2): `id` = `conflict_id`, `operation_id`, `entity_type`, `entity_id`, `kind`, `fields_json`, `base_version`, `server_version`, `server_value_json`, `client_value_json`, `status` (`open`, `resolved_server`), `created_at_utc`. The outbox row becomes `conflict`; no further operation for that entity is sent until S3.
9. **Rejected is terminal.** `state = rejected` rows are history. Recovery enqueues a **new** `operation_id` (wire contract 2 and 3.1). The corrected operation is built from current local state, not by editing the rejected row.
10. **`sync_state`** singleton: `user_id`, `device_id`, `cursor`, `state`; `meta.user_id` binds the database to one user and the owner id constant comes from it (CR REQ-4). Tests: `db_bound_to_single_user`, `device_id_created_once_and_persisted`, `second_user_open_is_refused`.
11. **Tombstone order.** Deleting a task or project with descendants writes tombstone operations leaf-first then the parent, in one transaction, in `seq` order (D-P; CR REQ-6).
12. **Crash recovery.** `in_flight` rows return to `pending` on start (the server replays by `operation_id`, so resending is safe) (plan S5 test `crash_in_flight_returns_to_pending`).
13. **A pull never overwrites a field with a pending operation** (CR REQ-5; pull is S6).

## 3a. Corrections by owner direction (2026-11-12 reconciliation)
These override anything else in this document and in CR-2A-001 where they differ.
| # | Rule | Replaces |
|---|---|---|
| C1 | **v1 to v2 ordering uses the verified v1 `rowid` order, not `created_at_utc`.** `sync_outbox` in v1 is an ordinary rowid table (TEXT primary key, no `WITHOUT ROWID`), so `rowid` is the insertion order the repository wrote; `created_at_utc` comes from the device clock and can go backwards (clock changes), so ordering by it can reorder dependent operations. The order is read from the original file inside the migration transaction. A backup copy is never the source of order: SQLite documents that `VACUUM` may renumber rowids of tables without an explicit `INTEGER PRIMARY KEY`, so a copy made that way can differ. | `ORDER BY created_at_utc, rowid` in CR-2A-001 and the first draft of the safety spec |
| C2 | **No automatic backup deletion.** The app never deletes, rotates, prunes or overwrites a SQLite backup on its own. Retention is an owner-controlled decision (O-10, open). | the first draft's "keep until the next successful start on v2 and then keep one" |
| C3 | **Ambiguous historical outbox states are preserved.** v1 `sent` (delivery unknown) and `failed` (cause unknown) rows, and the local `version` of rows whose create was `acked` without a stored server result, are carried into v2 **without automatic replay, without version reset and without loss**: no migration step or startup step sends them, changes their state, rewrites their `base_version`, or resets or recomputes a local `version`. Their user-visible handling (review, resend, discard) is a later decision. The v2 representation of these rows is an open design point (S5-Q1): it is not decided here, and it must not drop them. | the CR proposal's `sent` to `pending` mapping (automatic replay) and the unmapped `failed` state |
Definitions of "ambiguous" in C3 are this document's reading of the instruction; the Session B text decides if it differs.

## 4. Tests to write in S5 (not in S5-0)
`seq_order_survives_restart`, `crash_in_flight_returns_to_pending`, `migration_v1_to_v2_keeps_pending_ops` (see the migration safety spec), `update_payload_contains_only_changed_fields`, `create_payload_contains_all_required_fields`, `unchanged_save_writes_no_outbox_row`, `ack_sets_version_from_server`, `rejected_row_is_immutable_and_recovery_uses_new_operation_id`, `conflict_mirror_matches_wire_conflict_object`, `delete_tree_writes_leaf_first_ops`, `delete_parent_does_not_leave_live_children`, `db_bound_to_single_user`, `device_id_created_once_and_persisted`, `second_user_open_is_refused`, `pull_does_not_overwrite_pending_field`. Wire-level examples for the mirror tests come from `supabase/tests/s2_contract_test.sql`.

## 5. Compatibility gates against the S2 wire contract (must hold before S5 is accepted)
| Gate | Check |
|---|---|
| G1 | Every outbox field maps to an S2 operation key; no extra keys (unknown keys are `invalid_op`) |
| G2 | Patches contain only allowed keys per entity type and never `owner_id`, `version`, `field_versions`, `change_seq`, timestamps, `deleted_at` |
| G3 | `base_version`: create 0; update/delete >= 1 |
| G4 | Result handling covers every status in the presence table (wire contract section 2) |
| G5 | The `conflict` object fits the local mirror without loss; both values preserved |
| G6 | Retry rules of wire contract 3.1 are implementable from the outbox states |
| G7 | `completed_at`/`status` handling matches the owner's decision (open: Option A requires the client to set both together) |
| G8 | Title length limit consistent with the server (200) |

## 6. Migration safety gates
See `docs/operations/s5-migration-safety-test-spec.md`. No v2 code merges without those tests passing on Windows CI, and no real user database is ever opened by a test.

## 7. Open points (not decided here; see the status register)
| # | Point | Source |
|---|---|---|
| S5-Q1 | **Representation of preserved v1 `sent` and `failed` rows in v2.** C3 fixes the requirement (preserve, no replay, no version reset, no loss). The CR proposal's mapping is withdrawn: `failed` unchanged violates the v2 CHECK and `sent` to `pending` is automatic replay. The representation is open. | defect in CR-2A-001 section 3 proposal; C3 |
| S5-Q2 | Stored `version` of a pending create (D-1 of Phase 2A); v1 stores a value `>= 1` with base 0 in the outbox | CR "Phase 2A response" |
| S5-Q3 | Title CHECK is 500 locally, 200 on the server | CR REQ-7 |
| S5-Q4 | Owner binding column name (`owner_id` vs `user_id`) | CR REQ-4 |
| S5-Q5 | `request_id` has no server meaning; keep it client-side only | wire contract 7 item 6 |
| S5-Q6 | Whether v2 also needs a per-entity `synced` flag | CR section 4 question 2 |
