# S9 plan: remove the direct table-write grants on `projects` and `tasks` (blocker B-10)

**This is a plan. It is NOT authorized, NOT written as a migration and NOT applied anywhere.** S9 is the activation-gate slice in `docs/coordination/status-register.md`. Reason for the plan: while `authenticated` can INSERT and UPDATE `public.projects` and `public.tasks` directly, a client can bypass the synchronization protocol (conflict detection, idempotency, history). The per-user advisory lock still serializes those writes and the guard triggers still enforce ownership and invariants, so the risk is protocol bypass and not data theft; it is recorded as R5 in `docs/operations/security-hardening-decision-record.md`.

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
