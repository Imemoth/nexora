# Hosted acceptance record, 2026-11-13 (TEST project `uicccaawtjvqggeufbez`)

Authorization: owner message "Phase 3 Combined Hosted Deployment & Acceptance" (TEST environment; no production users). Baseline head `bb2c5c5`. Procedure: `combined-hosted-acceptance-operation.md` (corrected in this operation: S9 and `profiles`; S3 stop-and-preserve). No service-role key was used. Credentials are not recorded anywhere in the repository.

## 1. Baseline read before any write
Six migrations (through S1 `20261112151851`); `auth.users` 1 row (`test@test.com`, email-confirmed, not anonymous); `projects`, `tasks`, `devices`, `sync_operations`, `sync_conflicts` all 0; `authenticated` `statement_timeout=8s`; PostgreSQL 17.11. It matched the expected baseline.

## 2. Migrations applied (one file per call, in order)
SHA-256 of every file was recomputed and equals the runbook table. Because the platform migration tool takes the SQL text, each applied function was then compared with a local reference built from the repository files: `md5(prosrc)` of every function in `public` and `nexora_private` after each step. All function bodies are identical to the repository (the only differences are two fixture-only helper functions that exist in the local bootstrap but are platform-owned on hosted).
| Step | File | Hosted version | Result |
|---|---|---|---|
| S2 | `20261112160000_nexora_sync_push.sql` | `20261113084613` | applied; hashes identical |
| S3 | `20261112170000_nexora_sync_resolve_revoke.sql` | `20261113085005` | applied; hashes identical |
| S4 | `20261112180000_nexora_sync_pull.sql` | `20261113091105` | applied; hashes identical |
| Throttle | `20261112185000_nexora_sync_throttle.sql` | `20261113091345` | applied; hashes identical |
| Response bound | `20261112186000_nexora_sync_response_bound.sql` | `20261113091606` | applied; hashes identical |
| S9 | `20261112190000_nexora_s9_revoke_direct_writes.sql` | `20261113094553` | applied after the acceptance run; ACL verified |
After S9: `projects` and `tasks` grant `authenticated` only `r`; `project_members` no client grants; `profiles` unchanged (`arw`, intended).

## 3. Real HTTP/JWT acceptance (`tool/hosted_acceptance.py`, hosted PostgREST and GoTrue, no mocks)
Two synthetic identities (`nx-accept-a@example.test`, `nx-accept-b@example.test`) were created for the run by a direct insert into `auth.users` with a password hash computed locally (the password for `test@test.com` was not supplied, so that account was not used for the automated run; it is untouched). Result: **main phase 47 checks, 44 passed at first run; the 3 failures were test-script defects, corrected and re-run (6 of 6 passed)**; **S9 phase 13 of 13 passed**.
Verified: sign-in returns a JWT (`expires_in` 3600) and refresh token, JWT validates at `/auth/v1/user`; no token, garbage token and the anon-role key are refused; device registration (idempotent, device limit field); project and task creation with parent/child; idempotent replay after a lost response returns the original result; `operation_id` reuse with another body is rejected; pull from cursor 0, incremental empty pull, forged future cursor refused; cross-user isolation (B pulls nothing of A, cannot use A's device, cannot update, plant, or resolve against A's data; direct reads return only the caller's rows); `nexora_private` is not exposed (406 Invalid schema); stale-base edit becomes a conflict, nothing applied, entity blocked until resolved, resolution (client wins) and its idempotent replay, resolved state visible on pull; deleting a parent with a live child is a conflict (no cascade); device revoke makes push and pull fail with `device_invalid` while the other device keeps working.
The three corrected checks: reading `sync_operations` returned the caller's own rows (correct; test now asserts "only own rows"); a "500 row" page counts changes plus conflicts (500 items, `has_more` true); the first burst test straddled a minute bucket, so it was redone aligned to a bucket: **120 pulls accepted, 20 refused with `rate_limited` (NX007), account recovered in the next window**.

## 4. Performance (hosted, wall time from the client, including network)
| Operation | Time | Response size | Status |
|---|---|---|---|
| Push of 100 operations (create tasks) | 811 ms | 83,193 B | 200, all applied |
| Pull page of 500 items | 507 to 658 ms | about 279 to 302 KB | 200 |
| Atomic tree delete, project with 1,000 descendants | 828 ms | 602 B | 200, `tree_deleted` 1001 |
| Push whose response would exceed 2 MiB (20 updates of 200 KB-notes tasks) | 620 ms | 73 B | refused `payload_too_large` (NX004), nothing recorded |
| The same 20 operations in halved batches | 4 calls, 4,012,988 B in total | | all applied |
| Pull page with large rows | 599 ms | 301,709 B | 200 (byte-bounded) |
All are far below the 4 s target and the 8 s hard timeout. No timeout, no data loss, no unhandled protocol failure.

## 5. S9 results over HTTP
Direct INSERT, UPDATE and DELETE on `projects` and `tasks` as the owner: all six refused (HTTP 403 `permission denied`). SELECT on both still works. `profiles` SELECT and UPDATE keep their intended permission. Creating a project and tasks through the RPC still works after S9.

## 6. Advisors and Auth
Security advisor: INFO `rls_enabled_no_policy` for `nexora_private.rate_bucket` and `rate_policy` (intended: no client policy, no client privilege) and WARN leaked-password protection disabled (platform setting, not needed in the test environment). Performance advisor: two unused-index INFO items on tables that held no data before this run. Auth findings: `auth-dashboard-audit.md` (2026-11-13 section).

## 7. Test data left in place (not deleted, by instruction)
`auth.users` 3 (`test@test.com`, the two synthetic identities); `projects` 4; `tasks` 1,022 (22 live); `devices` 6 (5 active); `sync_operations` 1,055; `sync_conflicts` 2; `nexora_private.rate_bucket` a few rows. `test@test.com` has no sync data. The synthetic accounts and rows can be deleted together with the test account at the end of development (deleting a user cascades its rows; `sync_operations` is append-only for clients, so removal is done by deleting the users).

## 8. Findings
No security defect found. Observations: the server correctly returns a bounded 400 with the stable message for every refusal; push needs `base_version` of the last known version, and callers that reuse a stale base get conflicts (by design); a per-user SELECT on `sync_operations` remains by design (own rows). One documentation error corrected (S9/`profiles`), one procedure added (S3 stop-and-preserve).
