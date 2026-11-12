# S3 / S4 wire contract: conflict resolution, device revocation, tree delete, incremental pull

Status of the slices and gates: `docs/coordination/status-register.md` (this document describes the contract only).
Builds on `docs/architecture/s2-wire-contract.md` (push and register) and ADR 0002. Migrations:
`supabase/migrations/20261112170000_nexora_sync_resolve_revoke.sql` (S3) and
`supabase/migrations/20261112180000_nexora_sync_pull.sql` (S4). Rollbacks: `supabase/rollback/20261112170000_rollback_s3_resolve_revoke.sql`,
`supabase/rollback/20261112180000_rollback_s4_sync_pull.sql`.

All four new entry points follow D-R: a `public` SECURITY INVOKER wrapper over a `nexora_private` SECURITY DEFINER function with
`search_path = ''` and `lock_timeout = 5s`. EXECUTE is granted to `authenticated` only (not to `anon`, `public` or `service_role`).
Every write path takes the per-user advisory lock before `change_seq` is drawn (D-L).

## 1. Atomic tree delete (S3 protocol extension of `push`)
A delete operation may carry `patch = {"tree": [{"id": uuid, "base_version": n}, ...]}` (at most 1000 entries, no duplicates, the
root is not listed). Without `tree` the S2 rule is unchanged (a parent with live children is a conflict, nothing cascades, D-P).
With `tree` the server computes every descendant of the root (project: all its tasks; task: the recursive parent chain) and:

| Condition | Result |
|---|---|
| manifest lists an entity outside the subtree, a foreign entity, a duplicate or the root | `rejected: invalid_patch` |
| patch has other keys or `tree` is not an array | `rejected: invalid_op` |
| a live descendant is missing from the manifest | `conflict: parent_has_live_children`, `server_value = {"live_children": [ids]}` |
| a listed descendant has a version above its `base_version` (edited after the client saw it) | `conflict: delete_edited`, `server_value = {"edited": [{"id","version","base_version"}]}` |
| otherwise | `applied`; all listed live entities and the root are tombstoned in one sub-transaction; the result carries `tree_deleted: n`; already tombstoned entries are skipped |

Consistency with D-P: the server deletes only what the client explicitly listed and verified by version; it never infers a cascade.
The manifest is stored in `sync_operations.patch` and covered by `request_hash`, so a replay of the same `operation_id` returns the
stored result and a changed manifest under the same id is `operation_id_reuse`. A tree conflict can be closed only with the
server strategy (section 2).

## 2. `public.nexora_resolve_conflict(p_device_id uuid, p_operation_id uuid, p_conflict_id uuid, p_resolution text, p_values jsonb default null) returns jsonb`
Strategies: `resolved_server` (accept the server state, applies nothing), `resolved_client` (apply the stored client patch over the
server version), `resolved_merged` (apply `p_values`, a patch over the allowed fields), `recreate_copy` (for `edit_deleted` and
`exists`: `p_values = {"new_entity_id": uuid}` creates a new entity from the client value; the original stays tombstoned;
conflict status `resolved_copy`). The resolution is recorded as an immutable `sync_operations` row with `op_type = 'resolve'`;
the conflict row is written once (`resolved_at`, `resolution_source`, `resolution_operation_id`) and its evidence (`server_value`,
`client_value`, `base_version`) is never changed.

Result: `{status: applied | rejected | conflict, conflict_id, resolution, error, entity, replayed}`. Rejection codes: `conflict_not_open`,
`strategy_not_allowed` (client strategy on a deleted entity, copy on a live entity, anything but server on a tree conflict),
`invalid_values`, `invalid_patch`, `parent_has_live_children`, `parent_invalid`, `not_found` (unknown or foreign conflict, nothing is
recorded), `operation_id_reuse`. Replay of the same `(user, operation_id)` returns the stored result (`replayed: true`).

## 3. `public.nexora_revoke_device(p_device_id uuid, p_target_device_id uuid) returns jsonb`
The caller must be an active device of the same user; the target must belong to that user (otherwise NX001, not distinguishable
from an unknown id). Idempotent. A revoked device is refused (NX001) by register, push, pull, resolve and revoke. Revocation frees a
slot of the ten-device limit (D-D). Local data on the revoked device is never touched by the server.

## 4. `public.nexora_sync_pull(p_device_id uuid, p_cursor bigint, p_limit int default 200) returns jsonb`
Result: `{"changes": [{"entity_type": "project"|"task", "row": {...}}], "conflicts": [conflict rows], "next_cursor": bigint, "has_more": bool}`.
* One ordered stream per user: projects, tasks and conflicts all draw `change_seq` (conflicts through the trigger `guard_conflict_seq`
  on insert and on resolution). Cursor values are not contiguous; a client must never infer a gap.
* `p_limit` is clamped to 500; below 1 is NX005. A page is also bounded to 1,048,576 bytes of row JSON; the first item is always returned.
* Tombstones are delivered permanently (D-T). Rows carry server-owned `version` and `field_versions` (D-V).
* A null or negative cursor, or one above the highest issued sequence, is NX006 `invalid_cursor` (stale or foreign cursors cannot be
  used to learn about other users). Repeating a pull with the same cursor returns the same page (idempotent) unless newer rows exist.
* Pulling is consistent with concurrent writers: a writer holds the per-user lock until commit, so a page can never skip a lower
  sequence that commits later (multi-session test with a negative control that removes the lock).

## 5. Error taxonomy
| SQLSTATE | Message | Meaning | Client action |
|---|---|---|---|
| 28000 | `unauthenticated` | token valid but the user does not exist | stop, sign in again, keep all local work |
| 42501 | `anonymous_not_allowed` | anonymous identity | stop, require a real account, keep local work |
| NX001 | `device_invalid` | unknown, foreign or revoked device | re-register once; if refused, pause as device revoked |
| NX002 | `device_limit` | ten active devices | surface to the user |
| NX003 | `batch_too_large` | more than 100 operations | halve the batch |
| NX004 | `payload_too_large` | over the size bounds | halve the batch; a single oversize operation stays pending with an error |
| NX005 | `invalid_request` | malformed arguments | defect, surface |
| NX006 | `invalid_cursor` | cursor not acceptable | reset the cursor to 0 once and pull again |
| 40xxx, 53xxx, 55xxx, 57xxx | transient | retry with backoff; replay is exact by `operation_id` |

## 6. Not covered
PostgREST and JWT verification are not exercised by any automated test in this repository (the integration harness sets the JWT
claims per transaction like PostgREST does). End-to-end HTTP acceptance on the hosted project remains an open gate in the register.
