# Phase 2A data contract alignment

Status: **implementation record for Phase 2A. Owner decisions are listed in section 5.**
Scope: local SQLite only. No Supabase code, no network, no sync engine, no schema change beyond migration v1.

## 1. Sources and their state

| Source | Where it lives | Note |
|---|---|---|
| Phase 3 requirements for Phase 2A (REQ-1 to REQ-8) | `docs/coordination/phase-2a-sync-requirements.md` on `claude/affectionate-turing-unzmd2` | Not on `main` or this branch. Read only. |
| Shared data contract (frozen for Phase 3) | `docs/architecture/data-contract.md` on `claude/affectionate-turing-unzmd2` | Not on `main`. Read only. |
| Phase 3 plan | `docs/superpowers/plans/2026-11-12-nexora-phase-3-sync.md` on `claude/affectionate-turing-unzmd2` | Not on `main`. Read only. |
| Hosted Supabase schema | Hosted project, read only | Migrations `20261112111349`, `20261112115809`, `20261112120132`, `20261112120149` applied. S1 `20261112130000` not applied, as the contract says. |

The source documents are on a branch that is not merged, and that branch continues to move. This branch does not depend on them. Once they reach `main`, link them from here.

## 2. Hosted schema check (read only)

Check constraints on the hosted `tasks` and `projects` tables match the canonical vocabulary:

- Status: `open`, `in_progress`, `review`, `done`, `archived`. Local CHECK: identical.
- Priority: `none`, `low`, `medium`, `high`. Local CHECK: identical.
- Title: 1 to 200 characters after trimming. Local domain and repository: 200 (see deviation D-3).
- Version: `> 0`, server-owned. Local CHECK: `> 0` (see deviation D-1).

## 3. REQ status

| ID | Requirement | Status in Phase 2A | Evidence |
|---|---|---|---|
| REQ-1 | Local `version` is server-owned. A local edit never changes it. `base_version` is the stored value, or 0 for a create | **Implemented** (task update, project update, soft delete). Stored version is never changed locally. `base_version` is 0 while the entity's create is pending | `sqlite_task_repository_test.dart`: "an edit ... keeps the server-owned version", "a project edit leaves its stored version unchanged", "a delete keeps the stored version", "once the create is acknowledged, an edit carries the stored server version" |
| REQ-2 | Outbox v2 as a forward migration: `seq` autoincrement, states `pending, in_flight, applied, conflict, rejected`, `request_id`, `sent_at`, `server_result_json` | **Not implemented.** Phase 3 slice S5, after an owner decision (section 5, item 1) | Migration v1 unchanged |
| REQ-3 | `upsert` maps to server `create` (base 0) or `update`; `delete` is a tombstone | **Encoded, not mapped.** Creates are written with base 0. Edits after a pending create also carry base 0. The mapping to server types is Phase 3 | Outbox tests |
| REQ-4 | `sync_state` singleton, local conflict mirror, `meta` user binding | **Phase 3.** `meta` already binds the database to one owner (`meta.owner_id`, created once) | `workspace_sqlite_test.dart`: "the owner id is created once and reused on every launch" |
| REQ-5 | Domain write and outbox row in one transaction; a pull never overwrites a field with a pending op | **Transaction: implemented.** Pull rules: Phase 3 | "failed writes ... no partial row or outbox entry" |
| REQ-6 | Delete of a parent with descendants writes leaf-first tombstones | **Phase 3.** Phase 2A has no delete in the UI, and `softDeleteTask` tombstones one row | Documented limitation |
| REQ-7 | `notes` stored as `''`; status and priority values; title max 200 | **Implemented:** notes are written as `''` (no NULL), and the read path tolerates legacy NULL. Status and priority match. Title is refused above 200 at the repository | "empty notes are written as empty text, never NULL"; "a title over 200 characters is refused" |
| REQ-8 | Local ids are UUIDv4, lowercase | **Implemented in the generator** (`RandomIdGenerator`, RFC 4122 version 4). Validation of ids on push is Phase 3 | Generator test (`random_id_generator_test.dart`) |

Acceptance checks named in the request document:

- `local_edit_does_not_change_version`: covered (task, project, delete).
- `domain_write_and_outbox_row_atomic`: covered by the rollback tests.
- `crash_in_flight_returns_to_pending`: Phase 3 (no `in_flight` state in Phase 2A).
- `seq_order_survives_restart`: Phase 3 (no `seq` column in Phase 2A). Insertion order is kept by `rowid`.
- `db_bound_to_single_user`: `owner_id` is stored and written to every row. Enforcement of the binding on open: Phase 3.
- `delete_tree_writes_leaf_first_ops`: Phase 3 (REQ-6).

## 4. Deviations, recorded

- **D-1 Stored version for an unacknowledged create.** The contract says a local create carries base 0. The stored `version` of a new local row is still 1, because migration v1 has `CHECK (version > 0)`, and the server-owned default is 1. Operations derive base 0 from a pending create in the outbox (`_baseVersionFor`). This is correct for the outbox. It is not what the contract text says about the stored value. Resolution needs owner decision 2.
- **D-2 Phase 2A plan §2.1.** The plan's "+1 per committed update" and the server conflicts it listed (`review`, `archived`, `none`, nullable notes) are superseded by this document. The server accepts those values now.
- **D-3 Title CHECK on the table.** The local CHECK allows 500 characters. The repository refuses titles above 200, and the domain caps at 200, so the table is looser than the contract but no path writes more than 200. Tightening the CHECK needs a table rebuild in a migration. Resolution needs owner decision 3.
- **D-4 Outbox rows are not coalesced.** One row is written per committed change, as in migration v1. Phase 3 coalesces per entity when it sends.

## 5. Owner decisions needed before Phase 3 (S5)

1. **Outbox v2.** Approve the forward migration in the Phase 3 plan §4.2 (`seq`, the new states, `request_id`) as the Phase 3 S5 change. It is not part of this pull request.
2. **Stored version for a pending create (D-1).** Either relax the CHECK to `>= 0` in the same migration v2, so the stored value can be 0 until the server acknowledges the create, or keep the derivation in `_baseVersionFor`. Option 1 matches the contract text.
3. **Title CHECK (D-3).** Tighten the table to 200 in migration v2, or accept the repository and domain as the only enforcement.
4. **Name of the owner binding.** The contract calls it `meta.user_id`. Phase 2A stores `owner_id`. Confirm the name before Phase 3.

## 6. Not in this change

- No Supabase write, no schema change to the hosted project, no sync, no network code.
- No change to user-facing behaviour.
- No new dependency. The only dependency change is the owner-approved `sqlite3` 3.9.1 and the packages its build hook needs (see the pull request description).
