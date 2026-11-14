# Phase 3 S2 wire contract (device registration and push)

Status: **frozen before coding; amended 2026-11-12 (consolidation: `version_before`, `conflict` detail, retry semantics, limits; owner confirmations in section 7); implemented by `supabase/migrations/20261112160000_nexora_sync_push.sql` (local and PostgreSQL 17 CI only, NOT applied to hosted).** Source of authority, in order: owner decisions (`decisions/0002-sync-protocol.md`), the S0 contract (`data-contract.md`), the S2 plan (`docs/superpowers/plans/2026-11-12-nexora-phase-3-s2-push-rpc.md`), then this document. Where this document adds detail, it is marked **(addition)**. Items that need an owner decision are in section 7; nothing in section 7 is implemented as policy.

## 1. Endpoints
| Function | Kind | Returns |
|---|---|---|
| `public.nexora_register_device(p_device_id uuid, p_label text default null)` | SECURITY INVOKER wrapper | `jsonb` |
| `public.nexora_sync_push(p_device_id uuid, p_ops jsonb)` | SECURITY INVOKER wrapper | `jsonb` |
| `nexora_private.register_device`, `nexora_private.push` | SECURITY DEFINER, `search_path=''`, `lock_timeout=5s` | `jsonb` |
| `nexora_private.apply_operation`, `apply_core`, `sync_user`, `patch_spec`, `check_parent` | internal | no client EXECUTE |

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
`Result = {operation_id, status, error_code, version_before, applied_version, row, conflict_id, auto_resolved, conflict, replayed}`. Field presence by status (a key that is "absent" is not sent):
| Field | `applied` | `applied` + auto-resolved `sort_order` | `conflict` | `rejected` |
|---|---|---|---|---|
| `operation_id`, `status`, `replayed` | yes | yes | yes | yes (`operation_id` null only for an unusable one) |
| `error_code` | absent | absent | absent | yes |
| `version_before` **(addition, consolidation)** | yes | yes | yes | absent |
| `applied_version` | yes | yes | absent | absent |
| `row` | yes (authoritative row after the operation) | yes | yes (current server row, unchanged) | absent |
| `conflict_id` | absent | yes | yes | absent |
| `auto_resolved` | absent | `true` | absent | absent |
| `conflict` **(addition, consolidation)** | absent | yes (`status: resolved_server`) | yes (`status: open`) | absent |
- `version_before` = the entity's server `version` immediately before this operation: `0` for a create of a new entity; the unchanged version for no-ops (identical create, equal-value merge, empty patch, delete of an already tombstoned entity). `applied_version` = authoritative `version` after the operation. The client mirrors `version := applied_version` (and may use `version_before` to verify it acknowledged the operation it expected: `version_before` equals the `base_version` the client sent, or is greater when the server had moved on and the fields merged). Both values are stored in the immutable result, so a replay returns the **original** `version_before` and `applied_version` even if the entity has since changed.
- `conflict` = `{kind, fields, base_version, server_version, server_value, client_value, status}`, enough to populate the S5 local conflict mirror without a pull. `kind` is `field`, `exists`, `edit_deleted`, `delete_edited` or `parent_has_live_children`; `fields` is an array of field names; `base_version` is the base the client sent (0 for a create); `server_version` is the entity version when the conflict was detected; `server_value` and `client_value` are objects keyed by `fields` (for `delete_edited` and `parent_has_live_children` they are small descriptor objects, see section 5); `status` is `open` or `resolved_server`. It contains only data of the authenticated user: conflicts exist only on entities the caller owns (another user's id answers `rejected: not_found` with no `row` and no `conflict`). The `conflict` object equals the `sync_conflicts` row created for `conflict_id`.
- `status = rejected`: `error_code` set, nothing applied. A rejected operation is **terminal and immutable history**: the same `operation_id` is never reprocessed. Sending the identical operation replays the stored rejection (`replayed=true`). Sending the same `operation_id` with any changed field answers `rejected: operation_id_reuse` (not recorded, history unchanged). **Recovery after a rejection requires a new `operation_id`** with the corrected operation (the client keeps the rejected outbox row as history and enqueues a new one).
**Authoritative row** = every column of the entity row: projects `id, owner_id, name, description, color, is_archived, sort_order, version, deleted_at, created_at, updated_at, change_seq, field_versions`; tasks add `project_id, parent_id, title, notes, status, priority, due_date, completed_at` and omit the project-only columns.

## 3. Errors
Call-level errors are raised as exceptions (PostgREST returns HTTP 4xx with `{code, message}`); the message is the error code.
| Code | SQLSTATE | Where |
|---|---|---|
| `unauthenticated` | `28000` | no `auth.uid()`, a malformed `sub`, or the user no longer exists in `auth.users` (an existing token outlives a deleted user) **(addition)** |
| `anonymous_not_allowed` | `42501` | JWT claim `is_anonymous` true **or** `auth.users.is_anonymous` true (the authoritative flag, checked in addition to the claim; stricter than D-U, not different) **(addition)** |
| `invalid_request` **(addition)** | `NX005` | null device id, over-long label, `p_ops` not a non-empty array |
| `device_invalid` | `NX001` | unknown, another user's, or revoked device (same error for all) |
| `device_limit` | `NX002` | 10 active devices |
| `batch_too_large` | `NX003` | more than 100 operations |
| `payload_too_large` | `NX004` | call text over 1,048,576 bytes |
Per-operation rejections (in `results`): `invalid_op`, `invalid_patch`, `operation_id_reuse`, `not_found`, `parent_invalid`, `blocked_by_conflict`, `payload_too_large` (patch over 262,144 bytes). Transient database errors (classes 40, 53, 55, 57) abort the whole call and record nothing; unexpected errors also abort the call (bugs stay visible).

### 3.1 Retry semantics (client rules)
| Outcome | Meaning | Client action |
|---|---|---|
| Network failure, timeout, HTTP 5xx, `40001`, `40P01`, `55P03` (`lock_timeout`), `57014` (`statement_timeout`), any other `40/53/55/57` | The whole call is one database statement: nothing was recorded or applied | Retry the **same batch with the same `operation_id`s and unchanged payloads**, with backoff. A response that was lost in transit is recovered by the replay (`replayed=true`, original result). |
| `28000 unauthenticated` | No valid identity, or the user no longer exists | Refresh the session once; if still refused, stop and surface "signed out". Do not retry in a loop. |
| `42501 anonymous_not_allowed` | Anonymous identity | Stop; not retryable. |
| `NX001 device_invalid` | Device unknown, foreign or revoked | Re-register the device id once; if it is still refused (revoked), stop and surface. |
| `NX002 device_limit` | 10 active devices | Stop; user action needed. |
| `NX003 batch_too_large`, `NX004 payload_too_large` | Call over the limits | Split the batch; never resend unchanged. A single operation over the limits is a client bug. |
| `NX005 invalid_request` | Malformed call | Client bug; stop. |
| any successful call | Match results to operations **by `operation_id`** and check that the result count equals the operation count and the id sets are equal; never rely on position alone (a mismatch is treated as a transient failure and the batch is retried unchanged) |
| per operation `applied` | Acknowledged | Mark applied; set local `version := applied_version`; store `row` for the next pull to reconcile. |
| per operation `conflict` | Nothing applied; open conflict recorded | Mirror `conflict` locally; stop sending operations for that entity (they would answer `blocked_by_conflict`) until resolve (S3). |
| per operation `rejected` (any code) | Terminal | Do not retry the same `operation_id`. Fix the cause and enqueue a **new** operation. `blocked_by_conflict` is retryable only after the conflict is resolved, again as a new operation. |
| `rejected: operation_id_reuse` | The payload under that id changed | Client bug. The in-flight payload is immutable (S5). |

### 3.2 Limits and sizes
| Limit | Value | Enforced as |
|---|---|---|
| Operations per call | 1 to 100 | `NX003` over 100, `NX005` empty |
| Patch size | 262,144 bytes (jsonb text) | per operation `rejected: payload_too_large` |
| Call size | 1,048,576 bytes (`p_ops` text) | `NX004` |
| Active devices | 10 | `NX002` |
| Statement time | the platform's 8 s for `authenticated` (inherited); `lock_timeout` 5 s | `57014` / `55P03` (retry rule above) |
| **Response size** | **not bounded by a rule today.** Each result carries the authoritative row; a task row can hold up to the patch limit in `notes`, so the theoretical worst case is about 100 x 256 KB. Typical rows are under 2 KB. | **Open owner decision D-RESP** (options: omit `notes` from `row` above a size, lower the batch limit, or bound the sum of row sizes). Not implemented. |
Because the result is also stored in `sync_operations.result`, oversized rows add to log growth (see `docs/operations/security-hardening-decision-record.md`).

## 4. Idempotency and recording
1. Lock the user (`pg_advisory_xact_lock`, same key as S1). 2. Look up `(user_id, operation_id)`. 3. Same `request_hash` returns the stored `result` with `replayed=true` (the **original** result, including the row and version as they were then; current state arrives through pull). The same operation twice in one batch replays the second; a different hash returns `rejected: operation_id_reuse` (not recorded, the key is taken). 4. Otherwise validate, authorize and apply inside a sub-transaction. 5. Insert the final result row once (append-only).
`request_hash = sha256(entity_type | entity_id | op_type | base_version text | patch text)` over the values as supplied (jsonb text is canonical). Recorded (`server_seq` is the value of `nexora_private.change_seq` at processing time, monotone per user, not the entity's `change_seq`): `applied`, `conflict` and `rejected` with valid identity fields. Not recorded: `invalid_op` for an unusable `operation_id`/`entity_type`/`entity_id`/`op_type`, and `operation_id_reuse`. Concurrent duplicates serialize on the user lock.

## 5. Operation semantics
- **Allowed patch keys.** project: `name, description, color, is_archived, sort_order`. task: `parent_id, title, notes, status, priority, due_date, completed_at, sort_order`; create adds `project_id` (task). Anything else, including `owner_id`, `user_id`, `version`, `field_versions`, `change_seq`, `created_at`, `updated_at`, `deleted_at`, `id`, is `rejected: invalid_patch`. JSON types are checked per key; `null` only for nullable columns.
- **Ownership.** The owner is always `auth.uid()`. A missing entity and another user's entity both give `rejected: not_found`.
- **create.** Task: live project owned by the caller (else `not_found`; tombstoned project `parent_invalid`); parent, if given, live in the same project (else `parent_invalid`). Existing id of the caller with equal supplied fields: `applied` no-op; different fields or a tombstoned entity: `conflict` kind `exists`. Existing id of another user: `rejected: not_found`.
- **update.** Tombstoned: `conflict` kind `edit_deleted` (D-E). Per supplied field: equal to the current value is a no-op merge; otherwise it conflicts iff `field_versions[f] > base_version`. Any non-`sort_order` conflict makes the whole operation a `conflict` (D-A): nothing applied, one `sync_conflicts` row with `kind=field`, `fields`, both values. A `sort_order`-only conflict is auto-resolved server-wins (D-O): the other fields apply, `sort_order` keeps the server value, and a conflict row is stored already resolved (`resolution_source=auto_policy`, `resolution_policy=sort_order_server_wins`) preserving both values.
- **delete** (tombstone, D-T/D-P). Already tombstoned: `applied` no-op **(addition)**. Live children (tasks under a task or project): `conflict` kind `parent_has_live_children`. Entity version newer than `base_version`: `conflict` kind `delete_edited`. Otherwise `deleted_at` is set (server time). Conflict descriptors: `parent_has_live_children` has `fields=["deleted_at"]`, `server_value={"live_children": true}`, `client_value={"op": "delete"}`; `delete_edited` has `fields=["deleted_at"]`, `server_value={"version", "field_versions"}`, `client_value={"op": "delete", "base_version"}`; `edit_deleted` has `server_value={"deleted_at"}` and the whole client patch as `client_value`.
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

## 7. Owner decisions: status after consolidation (2026-11-12)
Recommendations are not approvals. "Owner direction" quotes the consolidation instruction of 2026-11-12.
| # | Item | Status |
|---|---|---|
| 1 | **`completed_at` / `status` consistency** | **Open, specified, not enforced.** Proposed rule (Option A, validate only): `status = done` requires a non-null `completed_at`; any other status requires it null; a violating operation is `rejected: invalid_patch` with nothing applied. The client supplies both fields, which keeps the approved S0 contract (`completed_at` is a client-supplied patchable field). Option B (server derives `completed_at`) conflicts with S0 and is **not recommended without an explicit contract change**. Prototype and 9 local tests exist outside the default run: `supabase/proposed/completed_at_rule_option_a.sql`, `supabase/tests/proposed/`. Current behavior (tested in `s2_contract_test.sql`): `completed_at` is an ordinary field with no cross-field rule. Needs owner approval before it becomes a migration; hosted data is empty so no legacy rows violate it. |
| 2 | sort_order mixed patches | **Confirmed by owner direction**: a `sort_order` conflict resolves server-wins (D-O) and never blocks the other fields of the same operation; the other fields apply and a resolved, auditable conflict row keeps both values. If a non-`sort_order` field also conflicts, the whole operation is a conflict (D-A) and nothing applies. Tested (`s2_contract_test.sql`, `so_*`). |
| 3 | Tombstoned parent on create | **Confirmed by owner direction**: creating under a tombstoned project or task is `rejected: parent_invalid` (terminal, recorded). The Phase 3 plan's `create_under_tombstoned_parent_conflicts` (S3) is superseded by this direction. Tested (`pi_*`). |
| 4 | Delete details | Unchanged: minimal implementation from approved decisions; S3 may refine. |
| 5 | Device revocation RPC | Open: no client revoke endpoint; `revoked_at` is honored. |
| 6 | `request_id` | Open: no server meaning. S5 may keep a per-attempt id client-side; S2 identifies work only by `operation_id`. |
| 7 | Exposed schemas | Partly verified read-only on 2026-11-12 (see the security record); the HTTP-level check remains part of the hosted gate. |
| 8 | Response size bound (D-RESP) | Open (section 3.2). |
| 9 | `blocked_by_conflict` is recorded as a terminal `rejected` (today). The S5 report asks whether it should instead be unrecorded and retryable after resolution (like `invalid_op`). | **Open (O-11).** Recommendation (not approved): keep terminal, recover with a new `operation_id` (consistent with OD-5). |
| 10 | Conflict kinds | S1 allows `field, edit_deleted, delete_edited, parent_deleted, parent_has_live_children, cycle, exists`; S2 emits `field, exists, edit_deleted, delete_edited, parent_has_live_children` (a tombstoned parent is `rejected: parent_invalid`, OD-4, so `parent_deleted` is not emitted; a cycle is rejected). |
| 11 | Client-side base handling | The S5 client keeps an observed base and sends a dependency-adjusted wire base (rule R in `docs/coordination/phase-3-s5-outbox-v2.md`), which relies on `version_before` and on the +1 version increment per changing update (tested by `s2_contract_test.sql`). |
