# Phase 3 S2 wire contract (device registration and push)

Status: **proposed freeze, written before any RPC code.** Source of authority, in order: owner decisions (`decisions/0002-sync-protocol.md`), the S0 contract (`data-contract.md`), the S2 plan (`docs/superpowers/plans/2026-11-12-nexora-phase-3-s2-push-rpc.md`), then this document. Where this document adds detail, it is marked **(addition)**. Items that need an owner decision are in section 7; nothing in section 7 is implemented as policy.

## 1. Endpoints
| Function | Kind | Returns |
|---|---|---|
| `public.nexora_register_device(p_device_id uuid, p_label text default null)` | SECURITY INVOKER wrapper | `jsonb` |
| `public.nexora_sync_push(p_device_id uuid, p_ops jsonb)` | SECURITY INVOKER wrapper | `jsonb` |
| `nexora_private.register_device`, `nexora_private.push` | SECURITY DEFINER, `search_path=''`, `lock_timeout=5s` | `jsonb` |
| `nexora_private.apply_operation(uuid, uuid, jsonb)`, `nexora_private.sync_user()` | internal | no client EXECUTE |

## 2. Request and response
**Register response:** `{"device_id": uuid, "created": boolean, "active_devices": integer}`. An existing active device of the caller returns `created=false` (idempotent). The label is stored at first registration only **(addition)**.

**Push request `p_ops`:** JSON array of 1 to 100 operations. Operation keys (unknown keys: `invalid_op`):
| Key | Rule |
|---|---|
| `operation_id` | required uuid; unique per user |
| `entity_type` | `project` or `task` |
| `entity_id` | required uuid (client generated, immutable) |
| `op_type` | `create`, `update`, `delete` |
| `base_version` | create: absent, null or 0 (stored as NULL because S1 requires `base_version > 0`) **(addition)**; update/delete: integer >= 1 and not ahead of the server version |
| `patch` | object. create and update: required. delete: absent or `{}`. An absent key is untouched; a present key with `null` sets NULL where the column is nullable |
| `client_created_at` | optional timestamp, informational only, never used for ordering |

**Push response:** `{"results": [Result, ...]}` in input order, one per operation.
`Result = {operation_id, status, error_code, applied_version, row, conflict_id, auto_resolved, replayed}`:
- `status = applied`: `applied_version` = authoritative `version` after the operation (unchanged for a no-op merge), `row` = authoritative server row, `replayed` boolean. `conflict_id` and `auto_resolved=true` appear only when a `sort_order` conflict was auto-resolved.
- `status = conflict`: nothing was applied; `conflict_id` set; `row` = current server row.
- `status = rejected`: `error_code` set; `row` null.
**Authoritative row** = every column of the entity row: projects `id, owner_id, name, description, color, is_archived, sort_order, version, deleted_at, created_at, updated_at, change_seq, field_versions`; tasks add `project_id, parent_id, title, notes, status, priority, due_date, completed_at` and omit the project-only columns.

## 3. Errors
Call-level errors are raised as exceptions (PostgREST returns HTTP 4xx with `{code, message}`); the message is the error code.
| Code | SQLSTATE | Where |
|---|---|---|
| `unauthenticated` | `28000` | no `auth.uid()` |
| `anonymous_not_allowed` | `42501` | JWT claim `is_anonymous` true |
| `invalid_request` **(addition)** | `NX005` | null device id, over-long label, `p_ops` not a non-empty array |
| `device_invalid` | `NX001` | unknown, another user's, or revoked device (same error for all) |
| `device_limit` | `NX002` | 10 active devices |
| `batch_too_large` | `NX003` | more than 100 operations |
| `payload_too_large` | `NX004` | call text over 1,048,576 bytes |
Per-operation rejections (in `results`): `invalid_op`, `invalid_patch`, `operation_id_reuse`, `not_found`, `parent_invalid`, `blocked_by_conflict`, `payload_too_large` (patch over 262,144 bytes). Transient database errors (classes 40, 53, 55, 57) abort the whole call and record nothing; unexpected errors also abort the call (bugs stay visible).

## 4. Idempotency and recording
1. Lock the user (`pg_advisory_xact_lock`, same key as S1). 2. Look up `(user_id, operation_id)`. 3. Same `request_hash` returns the stored `result` with `replayed=true`; a different hash returns `rejected: operation_id_reuse` (not recorded, the key is taken). 4. Otherwise validate, authorize and apply inside a sub-transaction. 5. Insert the final result row once (append-only).
`request_hash = sha256(entity_type | entity_id | op_type | base_version text | patch text)` over the values as supplied (jsonb text is canonical). Recorded: `applied`, `conflict` and `rejected` with valid identity fields. Not recorded: `invalid_op` for an unusable `operation_id`/`entity_type`/`entity_id`/`op_type`, and `operation_id_reuse`. Concurrent duplicates serialize on the user lock.

## 5. Operation semantics
- **Allowed patch keys.** project: `name, description, color, is_archived, sort_order`. task: `parent_id, title, notes, status, priority, due_date, completed_at, sort_order`; create adds `project_id` (task). Anything else, including `owner_id`, `user_id`, `version`, `field_versions`, `change_seq`, `created_at`, `updated_at`, `deleted_at`, `id`, is `rejected: invalid_patch`. JSON types are checked per key; `null` only for nullable columns.
- **Ownership.** The owner is always `auth.uid()`. A missing entity and another user's entity both give `rejected: not_found`.
- **create.** Task: live project owned by the caller (else `not_found`; tombstoned project `parent_invalid`); parent, if given, live in the same project (else `parent_invalid`). Existing id of the caller with equal supplied fields: `applied` no-op; different fields or a tombstoned entity: `conflict` kind `exists`. Existing id of another user: `rejected: not_found`.
- **update.** Tombstoned: `conflict` kind `edit_deleted` (D-E). Per supplied field: equal to the current value is a no-op merge; otherwise it conflicts iff `field_versions[f] > base_version`. Any non-`sort_order` conflict makes the whole operation a `conflict` (D-A): nothing applied, one `sync_conflicts` row with `kind=field`, `fields`, both values. A `sort_order`-only conflict is auto-resolved server-wins (D-O): the other fields apply, `sort_order` keeps the server value, and a conflict row is stored already resolved (`resolution_source=auto_policy`, `resolution_policy=sort_order_server_wins`) preserving both values.
- **delete** (tombstone, D-T/D-P). Already tombstoned: `applied` no-op **(addition)**. Live children (tasks under a task or project): `conflict` kind `parent_has_live_children`. Entity version newer than `base_version`: `conflict` kind `delete_edited`. Otherwise `deleted_at` is set (server time).
- **Open conflict.** Any operation on an entity that has an open conflict of the caller: `rejected: blocked_by_conflict` (resolution is S3).
- **Versions.** `version`, `field_versions`, `change_seq`, timestamps are server-owned (S1 guard trigger). The client never supplies them.

## 6. Cross-check
| Requirement | Source | Status |
|---|---|---|
| owner from `auth.uid()`, anonymous rejected | brief, D-U, plan | consistent |
| whole-operation atomicity (D-A), field-level conflicts (D-C) | ADR 0002 | consistent |
| permanent tombstones, no undelete (D-T, D-E) | ADR 0002 | consistent |
| sort_order server-wins with both values preserved (D-O) | ADR 0002 | consistent; mixed-field handling is an interpretation (section 7) |
| pending creates carry `base_version = 0` | S5 / data contract | consistent (accepted, stored NULL) |
| changed-fields-only updates | S5 / data contract | consistent (unsupplied keys untouched) |
| immutable in-flight payload, retry-safe `operation_id` | S5 | consistent: request hash covers the supplied values; a changed payload under the same id is rejected |
| ordered outbox, acknowledgements with authoritative versions | S5 | consistent: results are in input order with `applied_version` and `row` |
| append-only `sync_operations` (S1) | S1 | consistent: one insert with the final result |
| statement timeout 10 s in the S2 plan | plan | **corrected**: the platform gives `authenticated` an 8 s `statement_timeout`; the functions inherit it (a function-level 10 s would raise the limit). `lock_timeout` 5 s is set |
| JWT semantics | real hosted `auth.uid()/jwt()` definitions | the fixtures reproduce them exactly (`request.jwt.claim.sub` or `request.jwt.claims`; `is_anonymous` from `auth.jwt()`) |

## 7. Not implemented: owner decisions needed
1. **`completed_at` / `status` consistency.** No approved rule exists (the contract lists `completed_at` as a plain patchable field; Phase 2A sets it locally when a task becomes `done`). S2 treats `completed_at` as an ordinary field with no cross-field rule. Decision: should `done` require a non-null `completed_at` and other statuses a null one, and who derives it?
2. **sort_order mixed patches** (implemented as interpretation above): confirm that a `sort_order` conflict never blocks the other fields of the same operation.
3. **Tombstoned parent on create**: S2 rejects (`parent_invalid`); the Phase 3 plan lists a `parent_deleted` conflict for S3. Confirm which.
4. **Delete details** implemented minimally from approved decisions (already-tombstoned no-op; the two conflict kinds). S3 may refine.
5. **Device revocation RPC**: no revoke endpoint is specified; S2 honors `revoked_at` (set by an administrator) but offers no client revoke.
6. **`request_id`** (outbox v2 per-attempt id): no server semantics are specified; S2 identifies work only by `operation_id`.
7. **Exposed schemas**: Data API exposure is platform configuration (not a database setting). It must be verified on the real project before any S2 hosted apply.
