# V1 hardening implementation record (throttle, response bound, S9, limit measurements)

Scope: SQL and protocol hardening for the V1 release candidate. Everything here was built and tested on **disposable local PostgreSQL 16**
(the CI workflow `supabase-schema-tests` runs the same scripts on PostgreSQL 17 service containers). **Nothing was applied to any hosted
project; no hosted tool was used.** Hosted application is part of the single combined deployment operation and needs explicit authorization.

## 1. What was built
| Item | File | SHA-256 |
|---|---|---|
| Per-user throttle (private tables `rate_policy`, `rate_bucket`, function `nexora_private.throttle`; the five private entry points call it) | `supabase/migrations/20261112185000_nexora_sync_throttle.sql` | `bddbd3cd9defb28a23e4b74fa9c1c53e11ee89325d5f5ec564174bee83df6936` |
| rollback | `supabase/rollback/20261112185000_rollback_sync_throttle.sql` | `455e988838a8b1f393dfca244eade9dcba042fb0492f1f57dcbd0bb82c6c8eec` |
| Push response bound (replaces only `nexora_private.push`) | `supabase/migrations/20261112186000_nexora_sync_response_bound.sql` | `9734ac8add8dbecd1d80d2db8fd0c81a0d81745e58d9dc48bd416b0b2d5653d5` |
| rollback | `supabase/rollback/20261112186000_rollback_sync_response_bound.sql` | `afbe73109bf94f91ca688fded152dc04d4ab8236808f45e002c8f49e087242f0` |
| S9 direct-write revocation | `supabase/migrations/20261112190000_nexora_s9_revoke_direct_writes.sql` | `42086e9a0603fc9def9c582251f35657a54f7365de37fa0a3940dc571766e34c` |
| rollback | `supabase/rollback/20261112190000_rollback_s9_direct_writes.sql` | `417a61922699df5851b4e2c0da42b4895358cca3b8c1e61994e2a2811901a9b2` |

Recompute with `sha256sum` before any hosted use; the deployment record must cite the values it actually applied. Order: S2, S3, S4,
then throttle (185000), response bound (186000), S9 (190000). Contract: `docs/architecture/s3-s4-wire-contract.md` sections 5 to 7.
New SQLSTATE: **NX007 `rate_limited`**.

Design points: fixed one-minute buckets per (user, kind in pull/write); one atomic upsert-and-check; a refused call raises and so rolls
back its own increment (exactly `limit` calls succeed per bucket); limits are data (`rate_policy`: 120 pull calls, 120 write calls,
6,000 operations per minute); throttle sits after authentication and after request-size validation, before the per-user advisory lock;
tables carry RLS and no client privilege; lazy pruning removes at most 20 buckets older than 10 minutes per call of the same user.
S9 revokes INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES and TRIGGER on `projects`, `tasks`, `project_members` from `public`, `anon`,
`authenticated`; SELECT, `profiles`, `service_role` and all RLS policies are untouched.

## 2. Test evidence (local PostgreSQL 16)
`supabase/tests/run_local.sh` order: build from the fixture, apply every migration except S9, run the legacy suites that write directly as
`authenticated` (`fix_projects_update_guard_test` 29, `rls_and_contract_test` 57, `s1_sync_schema_test` 43, `s2_pre_s9_grants_test` 3),
apply S9, then every other suite on the final state; it prints `ALL SUITES PASSED`.
| Suite | Assertions |
|---|---|
| `s10_throttle_test.sql` (limit reached and refused, exact count, kinds independent, other users unaffected, ops budget, replay weight, pre-throttle validation, failed calls consume nothing, window rollover, bounded pruning, grants, definer settings, user-delete cascade) | 40 |
| `s10_response_bound_test.sql` (100 tiny updates echoing ~200 KiB rows refused NX004 with nothing recorded; halving converges; single operation always answered; replays; normal batch unaffected) | 36 |
| `s9_direct_writes_test.sql` (42501 matrix for authenticated and anon, SELECT under RLS, profiles, five RPCs end to end, isolation, ACL catalog) | 49 |
| `s2_auth_grants_test.sql` (matrix extended with `throttle`, post-S9 grants, rate tables closed) | 29 |
| existing suites unchanged: s2_apply 89, s2_contract 47, s2_device 23, s2_push 49, s2_security_direct 41, s3_resolve 68, s3_revoke 28, s3_tree_delete 39, s4_pull 111 | |

Other proofs: `concurrency/s10_throttle_concurrency.sh` (16 concurrent pulls with limit 5: exactly 5 succeed, 11 refused, counter 5, other
user unaffected); `verify_rollbacks.sh` (catalog snapshot including table ACLs and policies: S9 rollback, response-bound rollback and
throttle rollback each restore the previous catalog exactly; S9 rollback and forward are idempotent; rollback then re-apply reaches the
identical final catalog); `measure_limits.sh` (see section 3); existing concurrency scripts keep their negative controls (the controls now
also neutralize the throttle, whose counter row lock would otherwise serialize writers and hide a removed advisory lock; `lock_discipline.sh`
builds pre-S9 databases because it writes directly).

Mutation checks (`mutation_checks.sh`): 52 mutations in total, 16 of them new for this package (throttle never refuses, operation budget
ignored, shared counter for both kinds, pull / push / resolve not throttled, push weighs zero operations, throttle callable by
authenticated, rate policy writable, response bound removed or far too high, S9 forgetting tasks, leaving UPDATE or INSERT granted, also
revoking SELECT). Existing mutations now also mutate the replacing definitions in the new migrations. Result: caught=52 missed=0 (one initially equivalent mutation, "leaves DELETE granted", was replaced because authenticated never held DELETE: revoking it is a no-op).

## 3. Measured limits (local PostgreSQL 16, ceilings asserted generously for CI)
| Case | Measured | Ceiling |
|---|---|---|
| 100-operation push, 894,892-byte request | ~130 ms, response 932 KB | 5,000 ms; response at most 2,097,152 |
| 500-row pull page | ~15 ms, response 1,002,460 bytes | 3,000 ms |
| resolve | ~2 ms | 1,000 ms |
| tree delete, 1,000 descendants (request 67,010 bytes) | ~70 ms | 8,000 ms |
| largest accepted push response (ten echoed ~200 KiB rows) | ~30 ms, 2,006,323 bytes | 5,000 ms; below 2,097,152 |
These are local single-session numbers on an idle machine. They say nothing about hosted latency, cold caches or network; the hosted
measurement step of the combined deployment operation repeats them against the hosted project.

## 4. What the Dart client must change
* Map SQLSTATE NX007 / message `rate_limited` to a retryable server error and let the engine back off (retry later, never mark operations
  failed, never discard local work). NX004 handling (halve the batch) already covers the new push-response refusal.
* No other protocol change. Clients that predate NX007 treat an unknown SQLSTATE as a generic failure, so deploy the client mapping
  before enabling the throttle for real users.

## 5. What is NOT verified
* No hosted execution, no PostgREST/HTTP exercise of the new functions (the HTTP/JWT workflow has to be re-run against the new migrations).
* The hosted default statement timeout and real latency are unmeasured; the ceilings above are local.
* The throttle numbers are starting values, not tuned from traffic; the 2x boundary-burst tolerance is a documented property, not a defect.
* Operation-log retention is a design only (`docs/operations/rate-limit-and-log-retention-recommendations.md` section 3a); nothing purges.
* PostgreSQL 17 results come from CI on the exact pushed head, not from this local PostgreSQL 16 run.
