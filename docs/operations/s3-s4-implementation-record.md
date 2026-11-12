# S3 and S4 implementation record (local, not applied to hosted)

Contract: `docs/architecture/s3-s4-wire-contract.md`. Status, gates and decisions: `docs/coordination/status-register.md`.
Authorization: owner message "Phase 3 Complete S3 + S4 + S6 Implementation" (2026-11-12). No hosted write was made; neither migration
was applied to the hosted project.

## 1. What was built
| Item | File |
|---|---|
| S3: atomic tree delete in `apply_core`, `resolve`, `revoke`, wrappers, constraints (`resolve` op type, `resolved_copy` status) | `supabase/migrations/20261112170000_nexora_sync_resolve_revoke.sql` |
| S4: `change_seq` on `sync_conflicts` (trigger `guard_conflict_seq`), `devices.last_pull_at`, `pull`, wrapper | `supabase/migrations/20261112180000_nexora_sync_pull.sql` |
| Rollbacks (verified to restore the previous catalog; the S3 rollback aborts when resolve operations or `resolved_copy` rows exist) | `supabase/rollback/20261112170000_rollback_s3_resolve_revoke.sql`, `supabase/rollback/20261112180000_rollback_s4_sync_pull.sql`, `supabase/tests/verify_rollbacks.sh` |

## 2. RPC privilege inventory (new)
| Function | Kind | EXECUTE |
|---|---|---|
| `public.nexora_resolve_conflict(uuid, uuid, uuid, text, jsonb)` | INVOKER wrapper | `authenticated` only |
| `public.nexora_revoke_device(uuid, uuid)` | INVOKER wrapper | `authenticated` only |
| `public.nexora_sync_pull(uuid, bigint, integer)` | INVOKER wrapper | `authenticated` only |
| `nexora_private.resolve_conflict`, `revoke_device`, `pull` | DEFINER, `search_path = ''`, `lock_timeout = 5s` | `authenticated` (entry points called by the wrappers); revoked from `public`, `anon`, `service_role` |
| `nexora_private.guard_conflict_seq` | DEFINER trigger function | no direct EXECUTE grant |
`s2_auth_grants_test.sql` asserts the complete ACL matrix: seven public functions, ten EXECUTE grants for `authenticated`, none for `anon`.

## 3. Evidence (PostgreSQL 16 locally, PostgreSQL 17 in CI)
| Suite | Assertions |
|---|---|
| `s3_resolve_test.sql` (strategies, replay, reuse, cross-user, not_found, copy, tombstone preservation) | 68 |
| `s3_tree_delete_test.sql` (manifest grammar, live children, edited descendants, foreign ids, replay, tombstones) | 39 |
| `s3_revoke_test.sql` (own/foreign target, idempotency, revoked caller, slot freeing, refusal on every RPC) | 28 |
| `s4_pull_test.sql` (cursor, pagination, byte bound, tombstones, conflicts in the stream, multi-device, foreign and stale cursors, revoked device) | 111 |
| `concurrency/s3_s4_concurrency.sh` (pull never skips a sequence, with a negative control that removes the lock; concurrent resolutions; revoke against push) | 3 scenarios |
| `mutation_checks.sh` | 37 of 37 mutations caught (the harness mutates every migration that contains the mutated text) |
| `verify_rollbacks.sh` | catalogs restored exactly (289 and 284 lines compared) |
PostgreSQL 17 CI: workflow `supabase-schema-tests` run 43296292663 on `f7e742e` (success). Exact final head: see the status register evidence index.

## 4. Decisions made inside the authorization
* Tree delete is an extension of `push` (a `tree` manifest in the delete patch) rather than a new RPC: it reuses idempotency, ordering and history of S2. The server deletes only what the client listed and version-checked, so D-P and permanent tombstones are intact.
* Conflicts share the entity change stream (a trigger stamps `change_seq` on insert and on resolution) so one cursor orders everything a device must see.
* Pull is bounded by row count (500) and bytes (1 MiB; the first item is always returned so progress is guaranteed). This is a proposed answer to O-2 for pull; the push response bound stays open.

## 5. Not verified, unresolved
* No hosted deployment; PostgREST exposure, JWT verification and the 8 s statement timeout are unmeasured (B-8, B-9).
* Rate limiting and log retention are not implemented (O-3).
* Direct table INSERT/UPDATE grants on `projects` and `tasks` remain (B-10).
