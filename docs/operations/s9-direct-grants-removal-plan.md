# S9 plan: remove the direct table-write grants on `projects` and `tasks` (blocker B-10)

**Status update (V1 release-candidate package): the migration `supabase/migrations/20261112190000_nexora_s9_revoke_direct_writes.sql` and its rollback `supabase/rollback/20261112190000_rollback_s9_direct_writes.sql` are written and proven on disposable PostgreSQL (see section 9). They are NOT applied to any hosted project; hosted application stays unauthorized. The rest of this page is the original plan, kept as written.**

**Original statement: this is a plan. It was NOT authorized, NOT written as a migration and NOT applied anywhere.** S9 is the activation-gate slice in `docs/coordination/status-register.md`. Reason for the plan: while `authenticated` can INSERT and UPDATE `public.projects` and `public.tasks` directly, a client can bypass the synchronization protocol (conflict detection, idempotency, history). The per-user advisory lock still serializes those writes and the guard triggers still enforce ownership and invariants, so the risk is protocol bypass and not data theft; it is recorded as R5 in `docs/operations/security-hardening-decision-record.md`.

## 1. Why direct writes work today
`supabase/migrations/20261112115809_nexora_security_hardening.sql` revokes every table privilege from `anon` and `authenticated`, then grants back only what V1 needed: `SELECT, INSERT, UPDATE` on `public.profiles`, `public.projects` and `public.tasks` (no DELETE: tombstones only; the delete policies were dropped). `public.project_members` has no client privileges. RLS stays enabled on every table as the second layer. The synchronization RPCs (`nexora_private.push` and the S3 and S4 functions) write through SECURITY DEFINER code owned by `postgres`, so they do not depend on the client's table privileges.

## 2. Current grants (as asserted by `supabase/tests/s2_auth_grants_test.sql`, `direct_table_grants_unchanged_by_s2_s3_s4`)
Exact set for `authenticated` on `public` tables:
`devices:SELECT`, `profiles:INSERT`, `profiles:SELECT`, `profiles:UPDATE`, `projects:INSERT`, `projects:SELECT`, `projects:UPDATE`, `sync_conflicts:SELECT`, `sync_operations:SELECT`, `tasks:INSERT`, `tasks:SELECT`, `tasks:UPDATE`. `anon` has none (`anon_has_no_table_grants`).
Policies on `projects` and `tasks` (reproduced by `supabase/tests/00_bootstrap_local.sql`): owner select, insert and update; the owner delete policies were dropped by the hardening migration.

## 3. Proposed migration shape (to be written only after authorization)
A single additive-in-effect migration, for example `supabase/migrations/<timestamp>_nexora_revoke_direct_writes.sql`:
1. `revoke insert, update on public.projects from authenticated;` and the same for `public.tasks`. Keep `SELECT`: clients read through RLS (the pull RPC does not replace it for other features such as a future direct read), and removing it is a separate decision.
2. Leave `profiles` grants as they are unless the owner decides otherwise (profile editing is not part of the sync protocol).
3. Do not drop the owner insert and update policies in the same migration; they become inert and keep the catalog diff small. Dropping them is an optional second step.
4. Rollback script `supabase/rollback/<timestamp>_rollback_s9_direct_writes.sql`: the two `grant insert, update` statements, verified by the same catalog-snapshot approach as `supabase/tests/verify_rollbacks.sh`.
5. Hosted application follows the pattern in `docs/operations/hosted-deployment-checklist-s2-s4.md` (dry run in a rollback-only transaction, digest recorded, advisors before and after), each hosted step **[owner approval required]**.

## 4. Impact on existing tests
- `supabase/tests/rls_and_contract_test.sql` (Phase 2B regression, 57 assertions) inserts and updates `projects` and `tasks` as `authenticated` (for example "A inserts project", "A inserts task", "A updates with forged version", the cross-user and cycle checks). After S9 those statements fail with SQLSTATE 42501, so the suite must be split: the ownership, cycle, tombstone and invariant checks move to the RPC path (they are partly duplicated by `s2_apply_test.sql`), and a new group asserts that direct INSERT and UPDATE fail with 42501 for `authenticated` while SELECT under RLS still isolates users. The guard-trigger behaviour stays covered through the RPC suites because the triggers fire for every writer.
- `supabase/tests/s2_auth_grants_test.sql`: the expected string in `direct_table_grants_unchanged_by_s2_s3_s4` changes (remove `projects:INSERT`, `projects:UPDATE`, `tasks:INSERT`, `tasks:UPDATE`); rename the assertion to describe the new intent.
- `supabase/tests/fix_projects_update_guard_test.sql` and the mutation checks that use direct updates need the same review.
- Add mutation checks that re-grant the privileges and assert the suites fail.

## 5. Prerequisites (all must hold before S9)
1. Every shipped client version writes through the synchronization RPCs only. The Windows app today writes to local SQLite only, so no shipped client uses the direct path; confirm no other tool, script or dashboard automation writes these tables as `authenticated`.
2. Hosted S2, S3 and S4 are applied, verified and accepted, including the hosted HTTP/JWT acceptance (B-20), because after S9 the RPCs are the only write path.
3. The tombstone and conflict behaviour has been accepted in a real two-device run on the hosted project.
4. An owner decision on whether `SELECT` stays, and on `profiles`.
5. A kill-switch plan: the grants can be restored by the rollback script without data loss.

## 6. Test plan
1. Local PostgreSQL 16 and PostgreSQL 17 CI: the updated suites above, the new direct-write refusal group, mutation checks for the re-grant, the catalog snapshot of the migration and of its rollback.
2. Disposable HTTP environment: a PostgREST `POST /rest/v1/projects` as an authenticated user returns 401 or 403 (to be recorded); `POST /rest/v1/rpc/nexora_sync_push` still works.
3. Hosted: rollback-only dry run, the verification queries of the S2 to S4 checklist (grant matrix now without the four privileges), advisors, one RPC smoke test with a test account.

## 7. Rollback
Run the rollback script to restore `INSERT` and `UPDATE`; no data is touched by either direction. Clients that used the RPCs are unaffected.

## 8. Status and owner decisions
Not authorized and not applied. Decisions: when to schedule S9 relative to activation (recommended: in the same activation window, after hosted acceptance and before the first real user), whether `SELECT` and `profiles` stay, and whether the inert policies are dropped.

## 9. As implemented (deviations from the plan above)
- The migration revokes `INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER` on `public.projects`, `public.tasks` and `public.project_members` from `public, anon, authenticated` (broader than plan item 1: it removes every write-class privilege in one statement; only INSERT and UPDATE on projects and tasks were granted, so the rest is a no-op that guards against later accidental grants). `SELECT` stays; `profiles` is untouched; `service_role` is untouched; no policy is dropped.
- Rollback: `grant insert, update on public.projects, public.tasks to authenticated;`. `supabase/tests/verify_rollbacks.sh` proves that after the rollback the catalog snapshot (functions, constraints, triggers, columns, indexes, policies, table ACLs) is identical to the pre-S9 state, that the rollback and the forward migration are both idempotent, and that rollback then re-apply reaches the identical final catalog.
- The split of old suites (section 4) is done by ordering instead of rewriting: `supabase/tests/run_local.sh` builds the database, applies every migration except S9, runs the legacy suites that write directly as `authenticated` (`fix_projects_update_guard_test`, `rls_and_contract_test`, `s1_sync_schema_test`, `s2_pre_s9_grants_test`), applies S9, then runs every other suite on the final state. `supabase/tests/concurrency/lock_discipline.sh` builds its own pre-S9 databases because it writes directly.
- New suite `supabase/tests/s9_direct_writes_test.sql` (49 assertions): 42501 for INSERT, UPDATE, DELETE and TRUNCATE on the three tables for `authenticated` and `anon`, own rows included; SELECT under RLS still isolates users; profile insert and update still work; all five RPCs work end to end as `authenticated`; another user cannot modify a foreign task through the RPC; the ACL catalog has no write privilege left. `s2_auth_grants_test.sql` now asserts the post-S9 grant string.
- Mutation checks that break S9 (forgotten tasks table, UPDATE or INSERT left granted, SELECT also revoked) are caught.
- Not yet done: the disposable HTTP check that `POST /rest/v1/projects` is refused (section 6 item 2) belongs to the hosted-style HTTP workflow and is part of the combined hosted deployment record, not of this migration.
