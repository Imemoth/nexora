# Phase 3 S2 implementation record (2026-11-12)

**S2 is implemented locally and verified on PostgreSQL 17 CI. It is NOT applied to the hosted project, not exposed, and synchronization is not activated.** Contract: `docs/architecture/s2-wire-contract.md`. Plan: `docs/superpowers/plans/2026-11-12-nexora-phase-3-s2-push-rpc.md`.

## Artifacts
| Item | Path |
|---|---|
| Migration (functions only) | `supabase/migrations/20261112160000_nexora_sync_push.sql` |
| Rollback (verified: restores the S1 catalog exactly, 104 catalog lines identical) | `supabase/rollback/20261112160000_rollback_s2_sync_push.sql` |
| Suites | `supabase/tests/s2_auth_grants_test.sql`, `s2_device_test.sql`, `s2_apply_test.sql`, `s2_push_test.sql`, helper `s2_helpers.sql` |
| Multi-session test with negative control | `supabase/tests/concurrency/s2_duplicate_push.sh` |
| Mutation checks | `supabase/tests/mutation_checks.sh` |
| Fixture (hosted `auth.uid()/jwt()/role()` copied verbatim) | `supabase/tests/00_bootstrap_local.sql` |

## Functions and EXECUTE grants
| Function | Security | EXECUTE |
|---|---|---|
| `public.nexora_register_device(uuid, text default null)` | INVOKER, `search_path=''` | `authenticated` only |
| `public.nexora_sync_push(uuid, jsonb)` | INVOKER, `search_path=''` | `authenticated` only |
| `nexora_private.register_device(uuid, text)`, `nexora_private.push(uuid, jsonb)` | DEFINER, owner `postgres`, `search_path=''`, `lock_timeout=5s` | `authenticated` only |
| `nexora_private.apply_operation`, `apply_core`, `sync_user`, `patch_spec`, `check_parent` | `apply_*` DEFINER, others INVOKER, all `search_path=''` | `postgres` only |
`authenticated` also has `USAGE` on schema `nexora_private` (needed by the invoker wrappers). `anon`, `service_role` and `PUBLIC` have no EXECUTE on any S2 function. The suite compares the complete ACL set for every function in `public` and `nexora_private` against this table, and asserts the table grants, RLS and the set of `public` functions did not change.

## Test results (PostgreSQL 17.11, exact head `5df65e6`, [run 43260825024](https://github.com/Imemoth/nexora/actions/runs/43260825024))
| Suite | Assertions |
|---|---|
| F1 fix | 29 |
| Phase 2B regression | 57 |
| S1 | 43 |
| S2 apply (create, update, delete, conflicts, spoofing, authorization) | 89 |
| S2 auth and exact grants (JWT claims) | 27 |
| S2 devices | 23 |
| S2 push (idempotency, batches, limits, failure injection) | 49 |
| **Total** | **317, all passing** |
Multi-session: S1 lock scenarios A/B/C; S2 duplicate push A (one application, one replay), B (negative control without the push lock diverges: the second session hits the `sync_operations` primary-key backstop instead of a replay), C (another user is not blocked while user A holds the lock). Mutation checks: **17 of 17 deliberate breaks caught** (anonymous accepted, owner filter removed, replay skipped, operation_id reuse accepted, `auth.users` flag ignored, deleted-user token accepted, foreign device accepted, PUBLIC or `anon` EXECUTE granted, conflicts never detected, update after tombstone allowed, foreign-id create allowed, sort_order policy broken, transient errors recorded, spoofable keys accepted, open-conflict block ignored, batch limit removed).

## Security review of the implementation
| # | Finding | Status |
|---|---|---|
| 1 | An access token outlives a deleted user, and the token's `is_anonymous` claim can be stale | **Fixed**: `sync_user()` also requires the `auth.users` row and honors its `is_anonymous` flag (tests and mutations cover both) |
| 2 | My first negative control was not sensitive (the `devices` row lock serialized both sessions) | **Fixed**: the race uses two devices of one user |
| 3 | Dynamic SQL | Safe: table names come from a fixed `CASE`; columns are whitelisted keys passed through `quote_ident`; values travel as jsonb parameters |
| 4 | `register_device` and a create over another user's id reveal that an id exists (`device_invalid`, `not_found`) | Accepted, low: ids are random UUIDs and the error is the same for every case |
| 5 | Rejected and oversized operations are stored (up to 256 KB each, 100 per call) with no rate limit or retention | **Open**: needs a rate-limit and retention decision before activation |
| 6 | The platform gives `authenticated` an 8 s `statement_timeout`; a 100-operation call is one statement | **Open**: measure on the real project; the batch limit can be lowered |
| 7 | Anonymous and unauthenticated identities, forged owner, cross-user access, revoked and foreign devices | Covered by tests; PUBLIC, `anon` and `service_role` have no EXECUTE |
| 8 | Direct INSERT/UPDATE on `projects` and `tasks` is still granted (bypasses conflict detection) | Open until the S9 gate; the per-user lock covers those writes |

## Remaining client/server contract gaps
1. **`completed_at`/`status` consistency is not implemented** (no approved rule): needs an owner decision. `completed_at` is currently an ordinary field.
2. Phase 2A still sends whole-row payloads, does not re-base follow-up operations, stores version 1 for pending creates, has no outbox v2/`request_id`: S5/S6. S2 expects changed-fields-only patches and explicit `create`/`update`/`delete` with a fresh `base_version`.
3. No resolve (S3) and no pull (S4): an entity with an open conflict stays blocked, so synchronization must not be activated before S3.
4. No client revoke RPC; `request_id` has no server meaning.
5. Interpretations awaiting confirmation (wire contract section 7): sort_order mixed patches, tombstoned parent on create, delete details.

## Hosted deployment readiness: NO-GO today; the gate below is the path
The SQL-level security and JWT-semantics tests are complete (317 assertions, 17/17 mutations, PostgreSQL 17, claims fixtures copied from the hosted `auth` functions). What cannot be proven without touching the hosted project is the end-to-end HTTP path, so deployment is not ready until the owner approves a gate that includes:
1. Preflight: project, history of six migrations (S1 `20261112151851` last), no S2 objects, tables empty.
2. Hosted rollback-only dry run of the exact S2 file (as done for S1).
3. Verification of Data API exposure: `nexora_private` not in the exposed schemas; only the two wrappers appear as RPC.
4. HTTP-level checks with a real session token of a non-production test user (anonymous and signed-out calls refused, `authenticated` accepted), error-code mapping of the `NX00x` SQLSTATEs, and the 8 s `statement_timeout` behavior.
5. Rollback-only reruns of all suites on hosted, both Advisors, no persistent data.
Decisions to take first: the `completed_at` rule, the confirmations in section 7 of the wire contract, and rate limiting/retention.

## Recommended next owner approval
Approve (a) answers to the open decisions above, then (b) the hosted gate in this record, and (c) the scope and order of S3 (resolve) and S4 (pull), since activation is impossible without them.
