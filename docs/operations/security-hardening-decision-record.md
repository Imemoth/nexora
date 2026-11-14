# S2 security-hardening decision record (2026-11-12)

**Note (2026-11-14): this record describes the state at the time it was written. Statements such as "not applied to hosted", "disabled" or "not run" are historical; the hosted TEST deployment and Phase 3 acceptance are recorded in `docs/operations/hosted-acceptance-record-2026-11-13.md` and the current status is in `docs/coordination/status-register.md`.**

Scope: privileges and abuse resistance of the S2 functions in `supabase/migrations/20261112160000_nexora_sync_push.sql` (local and PostgreSQL 17 CI only, **not applied to hosted**). Method: catalog review, direct-call tests, mutation checks, and read-only queries on the hosted project. **No hosted permission, object or data was changed.** Recommendations below are not approvals.

## 1. Privilege inventory (as implemented; tested by `s2_auth_grants_test.sql` and `s2_security_direct_test.sql`)
| Object | Owner | Security | `search_path` | Granted to |
|---|---|---|---|---|
| schema `nexora_private` | `postgres` | n/a | n/a | `USAGE` to `authenticated` only (no `CREATE` for anyone but the owner) |
| `nexora_private.register_device`, `push` | `postgres` | DEFINER | `''`, `lock_timeout=5s` | `EXECUTE` to `authenticated` only |
| `nexora_private.apply_operation`, `apply_core` | `postgres` | DEFINER | `''` | owner only |
| `nexora_private.sync_user`, `patch_spec`, `check_parent`, `lock_user`, `user_lock_key` | `postgres` | INVOKER | `''` | owner only |
| `public.nexora_register_device`, `nexora_sync_push` | `postgres` | INVOKER | `''` | `EXECUTE` to `authenticated` only |
| sequence `nexora_private.change_seq`, all tables | n/a | n/a | n/a | no client privilege added; table grants and RLS unchanged by S2 |
`PUBLIC`, `anon` and `service_role` have no `EXECUTE` on any S2 function.

## 2. Can `EXECUTE`/`USAGE` on `nexora_private` be reduced?
The two public wrappers are SECURITY INVOKER (decision D-R), so they run **as the caller** and call `nexora_private.push` / `register_device` as the caller. The caller therefore needs `USAGE` on the schema and `EXECUTE` on exactly those two functions. Alternatives:
| Option | Effect | Assessment |
|---|---|---|
| A. Keep as is | `authenticated` can also call the two private entry points directly | Safe: the direct path performs the identical identity, device and ownership checks (41-assertion direct-call suite). Not exposed by the Data API as long as `nexora_private` is not an exposed schema. **Recommended.** |
| B. Make the public wrappers SECURITY DEFINER and revoke `USAGE`/`EXECUTE` on `nexora_private` | Removes the direct path | Contradicts D-R (INVOKER wrappers) and trips Supabase Security Advisor lint 0029 (a SECURITY DEFINER function in an exposed schema executable by signed-in users). The direct path is already harmless, so the gain is nil. Not recommended. |
| C. Expose no wrapper, call private only | Impossible: `nexora_private` must not be exposed | Rejected. |
Decision requested: **confirm Option A** (no change). Nothing can be removed without breaking the INVOKER wrappers.

## 3. Verification matrix
| Property | Evidence |
|---|---|
| Owner is always `auth.uid()`; client cannot name an owner | `s2_apply_test` spoofing group; `owner_id_in_patch_rejected`; `spoofed_owner_direct_call_changed_nothing` |
| Anonymous rejected (JWT claim and `auth.users.is_anonymous`), signed-out rejected | `s2_auth_grants_test`; `direct_push_anonymous_*`, `direct_push_without_uid_is_unauthenticated` |
| Deleted user with a still-valid token rejected | `deleted_user_with_a_valid_token_is_unauthenticated`; `direct_push_deleted_user_rejected` |
| Cross-user isolation (entities, devices, history, conflicts, operation ids) | `cross_user_history_invisible`, `cd_other_user_same_operation_id_is_independent`, foreign device and foreign id tests, no data leak in error results (`cd_foreign_*_no_leak`) |
| Direct-call bypass resistance | wrappers bypassed: same checks (`direct_push_*`); internal functions refused for `authenticated` and `anon` (`internal_denied_*`, 14 assertions); `authenticated` cannot create objects, use `change_seq`, or forge history rows |
| `search_path` and ownership | every S2 function has `search_path=''`, owner `postgres`; shadow-table test (`search_path_shadow_table_is_not_used`); injection-shaped keys, strings and entity types are refused or stored as data |
| History integrity | append-only; no UPDATE/DELETE even for the owner (`rj_update_history_blocked`, `rj_delete_history_blocked`) |
| Mutation sensitivity | 21 of 21 deliberate breaks caught (`supabase/tests/mutation_checks.sh`), including granting `sync_user` to `authenticated` and `CREATE` on the schema |
| Data API exposure (hosted, read-only, 2026-11-12) | `pg_graphql` is **not installed** (extension listing: `installed_version` null). Function EXECUTE counts on hosted: `public` 0 for `anon`/`authenticated`; `nexora_private` 0 for both (S2 not applied). The platform stub schema `graphql_public` has one function executable by `anon`/`authenticated` (Supabase default; unrelated to Nexora data). The exposed-schemas setting is platform configuration and **cannot be read through SQL**; it is verified at HTTP level in the hosted gate. `pg_net`, `http`, `dblink`, `pg_cron`, `pgmq` are available but **not installed**. |

## 4. Risks and options (recommendations, not approvals)
| # | Risk | Today | Options |
|---|---|---|---|
| R1 | **No rate limit.** A signed-in user can push 100-operation calls continuously; rejected and oversized operations are recorded too. | Open | (a) throttle per user using `devices.last_push_at` or a small counter inside `push` (cheap, same lock); (b) platform rate limits (Supabase Auth/API limits, not controllable per RPC); (c) store only the `request_hash` and error for rejected operations (cuts growth, loses the payload for debugging). Recommend (a) plus (c). Needs a design decision and a new migration. |
| R2 | **Log growth.** `sync_operations` stores patch (up to 256 KB) and result (row included) per operation; append-only. | Open | Estimate: typical operation under 4 KB; worst case about 0.5 MB each, up to 50 MB per call. With R1 unresolved the growth is unbounded per user. |
| R3 | **Retention is blocked by design.** The append-only guard also blocks any purge. | Open | A purge needs a deliberate guard change (a narrowly scoped privileged path such as a `SECURITY DEFINER` purge function running only for rows older than a horizon and only with acknowledged operations) or time partitioning (`pg_partman`, not installed). Horizon must exceed the client replay window. Recommend deciding the retention horizon first; nothing implemented. |
| R4 | `statement_timeout` is 8 s for `authenticated`; a 100-operation call is one statement. | Open | Measure on the real project in the hosted gate; the batch limit can be lowered (contract change). |
| R5 | Direct INSERT/UPDATE on `projects`/`tasks` is still granted; it bypasses conflict detection (the per-user lock still serializes it). | Open until S9 | Revoke at the S9 activation gate; do not change now (restriction). |
| R6 | Device cap 10 with **no client revoke RPC**: a user who reaches 10 devices cannot register an 11th. | Open | Add a revoke RPC (S2.1) or an admin procedure before activation (wire contract item 5). |
| R7 | An id's existence is observable (`device_invalid` vs `not_found`) | Accepted, low | Random UUIDs; the error is the same for every case. |
| R8 | Lock contention: a user's own slow call blocks that user's other calls (5 s `lock_timeout`). Other users are not blocked (tested). | Accepted | none |
| R9 | End-to-end HTTP path (real token, PostgREST error mapping, exposed schemas) is unproven. | Open | Hosted gate step 4 (needs separate approval). |

## 5. Hosted state
No change. The read-only queries above ran against the hosted project only (extension list, function EXECUTE counts). S2 remains unapplied; `anon` and `authenticated` still have no function EXECUTE in `public` or `nexora_private`.

## 6. Decisions requested
1. Confirm D-R Option A (no privilege change).
2. Rate-limit approach R1 and retention horizon/purge path R3 (design, then a migration after S3/S4 settle the log shape).
3. Revoke RPC R6.
4. D-RESP response-size bound (wire contract 3.2).
