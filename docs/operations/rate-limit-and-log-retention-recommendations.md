# Rate-limit and operation-log retention: recommendations (decision O-3)

**Status update (2026-11-14): the per-user throttle and the push-response bound are applied to the hosted TEST project (2026-11-13). Log retention and purge remain open and belong to production hardening, which is out of scope for now.**

**Update (V1 release-candidate package): the per-user throttle (section 2 item 3) is now implemented in `supabase/migrations/20261112185000_nexora_sync_throttle.sql` and tested locally; numbers and mechanics are in `docs/architecture/s3-s4-wire-contract.md` section 7. It is not applied to any hosted project. Operation-log retention (section 3 and the DESIGN in section 3a) is a design only: nothing is implemented. Everything not named here as implemented remains a recommendation, not applied or approved.** Decision O-3 stays open in `docs/coordination/status-register.md`. Background: risks R1 to R3 in `docs/operations/security-hardening-decision-record.md` and finding 5 in `docs/operations/s2-implementation-record.md`. Hosted state: none of the S2 to S4 functions is applied, so no traffic exists today.

## 1. What grows and what can be abused
| Surface | Cost per call | Why it matters |
|---|---|---|
| `nexora_sync_push` (up to 100 operations) | one statement, one per-user advisory lock, one `sync_operations` row per operation (patch up to 262,144 bytes, result with the entity row) | a signed-in user can loop it; rejected and oversized operations are recorded too |
| `nexora_sync_pull` (up to 500 rows or 1 MiB) | read only; no row written except `devices.last_pull_at` | cheap per call, but a tight loop on an old cursor repeats the same page |
| `nexora_register_device` | one `devices` row, capped at ten active devices per user (D-D) | bounded; revoked devices still count as history |
| `nexora_resolve_conflict`, `nexora_revoke_device` | one `sync_operations` row (resolve) or one `devices` update | small |
| Auth endpoints | platform rate limits | owned by the Auth configuration (`docs/operations/auth-dashboard-audit.md`) |

## 2. Rate limiting (recommendation R-1)
Layered, from cheapest to most specific:
1. **Gateway level (recommended first, no migration).** Use the platform's API/Auth rate limits and, if available on the plan, an edge rule on `/rest/v1/rpc/nexora_*` limiting requests per client IP and per token. Limits cannot be set per RPC by the platform itself, so this layer only caps volume.
2. **Client behaviour (already implemented in S6).** Backoff of 2 s doubling to 5 minutes with jitter; one cycle at a time; manual "Sync now" disabled while synchronizing; no background traffic when the flag is off. This reduces load from well-behaved clients only.
3. **SQL level per user (recommended second, needs a migration and an owner decision).** Inside `nexora_private.push` (it already holds the per-user lock, so the check adds no new contention): refuse with a new error code when the same user has performed more than N push calls in the last window, using `devices.last_push_at` (exists since S1) plus a small per-user counter row, or a count over recent `sync_operations.created_at`. Suggested starting values, to be tuned from the hosted measurement (`docs/operations/hosted-deployment-checklist-s2-s4.md` section 8): at most 60 push calls and 600 pull calls per user per minute, at most 10,000 operations per user per hour. A refused call returns a stable error code that clients treat as "retry later" (backoff), never as data loss. Needs a contract amendment in `docs/architecture/s3-s4-wire-contract.md` (new code in the taxonomy) and a client mapping before it can ship.
4. **Per device.** Count by `device_id` as well, so one misbehaving install cannot starve the user's other devices (they share the user lock). Recommendation: a per-device limit at half the per-user limit.
Alternatives considered: pgbouncer or Postgres connection limits (do not distinguish users); a dedicated Edge Function in front of the RPCs (adds a second trust boundary and a service-role key to protect; not recommended for V1).

## 3. Operation-log retention (recommendation R-2)
Facts from the schema (`supabase/migrations/20261112130000_nexora_sync_protocol_schema.sql`): `sync_operations` is append-only, guarded by `sync_operations_append_only` and `sync_operations_no_truncate`, enabled always; conflict rows are immutable except the single resolution write. The guard therefore also blocks any purge, so retention requires a deliberate change.
Design recommendation, to be approved before any migration:
1. **What may never be purged:** conflict evidence while the conflict is open or was resolved less than the review horizon ago; any operation referenced by a conflict (`operation_id`, `resolution_operation_id`); the most recent operation of each entity (needed for replay and for base-version reasoning); tombstoned entity rows (permanent by D-T and D-E, they are not part of this log).
2. **What may be purged after a horizon:** `applied` operations older than the horizon that are not referenced by a conflict and are not the latest operation of their entity; `rejected` operations older than the horizon.
3. **Horizon:** longer than the longest client replay window. A client replays an operation id until it receives an answer; a device that stays offline for weeks can still replay. Recommendation: 90 days after the operation was acknowledged, and never for operations of a device that is still active and has not pulled past that operation's sequence.
4. **Rejected operations: store the hash, not the payload (R1 to R3).** For `rejected` and oversized operations keep `request_hash`, `error` code and metadata, and store an empty `patch`. The replay answer for a rejected operation is the error code, which needs no payload. This cuts the worst-case growth (up to 262,144 bytes per rejected operation) without touching accepted history. Needs a migration that changes what `push` writes for rejected operations.
5. **Purge path:** a narrowly scoped SECURITY DEFINER function owned by `postgres`, executable by no client role, running as a scheduled job (the extension `pg_cron` is available but not installed; installing it is a separate owner decision) or by an owner-run procedure. It temporarily passes the append-only guard only for rows matching the purge rule (for example through a session setting checked inside the guard, readable only by the definer function) and writes a summary row of what it removed (counts per user, horizon). Alternative: monthly time partitioning with detach of old partitions (extension `pg_partman` is not installed). Recommendation: the function, because it keeps the guard intact for every other path and needs no extension beyond the optional scheduler.
6. **Tests required before approval:** a purge cannot remove a referenced operation, an open conflict's evidence or the latest operation of an entity; it cannot run as `authenticated`; a replay of an operation inside the horizon still returns the stored result; mutation checks that break each rule are caught (`supabase/tests/mutation_checks.sh` pattern).

## 3a. Retention DESIGN (not implemented; refines section 3)
**Status: design for owner review. No migration exists. Nothing is purged today and nothing may be purged before the checks in "Before enabling" pass.**

What may be purged, and when (horizon H = 180 days after `created_at`, configurable; chosen above the longest offline window the product
supports and above the 90 days recommended in section 3):
| Row class | Rule |
|---|---|
| `applied` operation, not the latest operation of its entity, not referenced by any conflict (`operation_id`, `resolution_operation_id`) | purge after H |
| `rejected` operation (any age beyond H) | purge after H; before that, at write time, store only `request_hash`, `error_code` and metadata with an empty `patch` (hash-only) |
| latest operation of each entity | never purged |
| operation referenced by an open conflict, or by a conflict resolved less than H ago | never purged |
| conflict rows, devices, tombstoned entities | not part of this purge |

Why the idempotency and replay guarantees survive. Replay protection means "the same `operation_id` is never applied twice." After a
purge the id is simply unknown, so a replay is evaluated as a new operation against the **current** server state:
* a replayed `create` finds the entity (an entity row is never purged; tombstones are permanent) and yields a `exists` conflict or a rejection;
* a replayed `update` or `delete` carries the `base_version` of the original attempt; the original application raised the entity (and the
  touched fields) above that base, so the server sees a stale base and returns a field conflict or `edit_deleted`, never a second application;
* the latest operation per entity is kept, so the most recent replay of every entity still receives its exact stored answer.
The only observable effect of a very late replay is a conflict the user resolves, not a double write. That is why H must exceed the longest
offline window: inside H, replays are exact. (This is a design argument from the current apply rules; it is not covered by a test in this
package, and the purge tests listed below must include it.)

Purge function shape: `nexora_private.purge_sync_operations(p_horizon interval, p_batch int default 1000) returns int`, SECURITY DEFINER,
owner `postgres`, `search_path = ''`, `revoke all from public, anon, authenticated, service_role`; deletes at most `p_batch` rows per
call ordered by `created_at` and returns the count, so a scheduler (or the owner) loops until it returns 0. It takes
`pg_try_advisory_xact_lock` on a purge key and returns 0 when another purge runs, and takes **no** per-user lock (it only removes rows no
live protocol decision can read: older than H, unreferenced, not latest). The append-only guard needs a narrow, transaction-local bypass
readable only by this function (a `set_config('nexora.purge', ...)` checked inside the guard with the definer as the only role that can
set it successfully), and every call writes one summary row (counts per class, horizon, time) to a private audit table.

Before enabling (all required): purge tests (cannot remove a referenced operation, open-conflict evidence, the latest operation of an
entity, or anything younger than H; cannot run as `authenticated`, `anon` or `service_role`; concurrent pushes during a purge neither
block longer than the lock timeout nor lose rows; replay of a purged `create`, `update` and `delete` yields conflict or rejection and never a
second application); mutation checks for each rule; a catalog-snapshot rollback proof; hosted size measurement showing growth justifies it
(sections 4 and 5); owner approval of H and of the scheduler (`pg_cron` or an owner-run procedure).

## 4. Growth estimates (order of magnitude, no measurements exist)
Assumptions, to be replaced by measurements after the hosted gate: a typical accepted operation stores a patch under 1 KB and a result with the entity row of about 1 KB, so about 2 to 4 KB per operation including indexes; a heavy user performs 200 operations per day; ten users.
| Quantity | Estimate |
|---|---|
| Per heavy user per day | 200 operations, about 0.4 to 0.8 MB |
| Per heavy user per 90 days (the proposed horizon) | about 36 to 72 MB |
| Ten heavy users per 90 days | about 0.4 to 0.7 GB |
| Worst case from one abusive client without limits | 100 operations of up to 262,144 bytes per call, about 25 MB per call; at one call per second this is over 2 GB per day |
The worst case is the reason R-1 and the rejected-operation hash rule (R-2 item 4) are recommended before activation. Pull traffic adds no storage.

## 5. Alerting (recommendation R-3)
Daily owner-readable queries or dashboard tiles, no automation required for V1:
- operations written per user in the last 24 hours (top five); alert above 5,000;
- size of `sync_operations` (table plus indexes) week over week; alert on 2x growth;
- count of rejected operations per user per day; alert above 500 (a client defect or abuse);
- calls refused for rate limits (once R-1 exists); open conflicts older than seven days; devices at the cap of ten.
Source: Supabase logs for the RPC paths (status 4xx/5xx rates, SQLSTATE NX001 to NX006) and catalog size queries.

## 6. Decisions requested from the owner
1. Approve or amend the rate-limit layers and numbers in section 2 (and whether SQL-level limiting is wanted before activation).
2. Approve the retention horizon and the purge-function design in section 3, or choose partitioning.
3. Approve storing only the hash for rejected operations (changes what S2 writes; replay answers stay identical).
4. Decide whether installing `pg_cron` is acceptable, or whether the purge stays an owner-run procedure.
