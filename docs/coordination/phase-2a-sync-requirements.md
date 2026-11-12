# Phase 3 requirements for the Phase 2A SQLite implementation

From: Phase 2B/3 server work (branch `claude/affectionate-turing-unzmd2`, see `docs/architecture/data-contract.md`, "Phase 3 additions").
To: owner of `feature/phase-2a-sqlite`. **This is a request. Nothing on the Phase 2A branch was changed.** Each item needs separate coordination before implementation.
Reference state reviewed: `origin/feature/phase-2a-sqlite` @ `9f71c15` (plan and `migrations.dart`).

## Required changes
| ID | Requirement | Why | Phase 2A today |
|---|---|---|---|
| REQ-1 | Local `version` is server-owned: set only from pull or ack, never incremented by a local edit; `base_version` of an op is that value (0 for create) | Server checks `base_version`; a local bump breaks conflict detection (D-V) | Plan §2.1 says "+1 per committed update" |
| REQ-2 | Outbox v2 as a forward migration (v2), never an edit of v1: `seq INTEGER PRIMARY KEY AUTOINCREMENT`; states `pending, in_flight, applied, conflict, rejected`; `request_id`; `sent_at`; `server_result_json` | Strict send order, crash recovery (`in_flight` -> `pending` on restart), idempotent resend | `operation_id` PK, states `pending/sent/acked/failed`, no order column |
| REQ-3 | Operation mapping: `upsert` with `base_version = 0` -> server `create`, else `update`; `delete` -> tombstone | Server types are `create/update/delete` | `upsert`/`delete`, `base_version >= 0` |
| REQ-4 | New tables: `sync_state` (singleton: `user_id`, `device_id`, `cursor`, `state`) and a local conflict mirror; `meta.user_id` binds the database to one user | Cursor, device identity, no cross-user push | none |
| REQ-5 | Domain write and its outbox row in one SQLite transaction (already planned, keep it); a pull never overwrites a field with a pending op | No lost edit | planned in §5.4 |
| REQ-6 | Delete of a task or project with descendants writes tombstone ops leaf-first plus the parent, in `seq` order | Server never cascades (D-P) | `deleteTask` is soft, one row |
| REQ-7 | `notes` stored as `''` (server column is `NOT NULL DEFAULT ''`); status `review/archived`, priority `none` are now valid server values; title max 200 | Server aligned in Phase 2B | §2.1 still lists these as server conflicts and `notes` as NULL: **stale** |
| REQ-8 | Local ids are UUIDv4, lowercase, validated | Server `uuid` | planned |

## Not requested
No Supabase code or package, no network, no authentication, no sync engine in Phase 2A. Phase 3 slices S5-S7 own those, after separate approval.

## Acceptance checks (to be run on the 2A side)
- `local_edit_does_not_change_version`, `domain_write_and_outbox_row_atomic`, `crash_in_flight_returns_to_pending`, `seq_order_survives_restart`, `db_bound_to_single_user`, `delete_tree_writes_leaf_first_ops`.
