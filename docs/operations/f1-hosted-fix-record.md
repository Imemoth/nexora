# F1: hosted `guard_row()` correction (applied 2026-11-12)

Target: Supabase project `uicccaawtjvqggeufbez` (PostgreSQL 17.11). Authorization: owner, narrowly for the standalone fix only. **S1 (`20261112130000`) was NOT applied.** Synchronization stays disabled; no grant, policy, RLS, authentication or sharing change.

## Result
| Item | Value |
|---|---|
| Hosted migration | `20261112142732_nexora_fix_projects_update_guard`, recorded exactly once |
| Repository file | `supabase/migrations/20261112125000_nexora_fix_projects_update_guard.sql` (name kept so it sorts before S1; the hosted version differs, see mapping) |
| File SHA-256 | `8090bc3b26705870e3a6513fd96f26341f833e6aa972a10135ac719680b0dc6d`, identical to the blob tested by PostgreSQL 17 CI run 43236184204 |
| Function before | md5 `6deb218ebcdc28a01fda4ec384046f27`, 1151 chars |
| Function after | md5 `305edd2eb7769b45807eac9b07287876`, 1238 chars (same hash as the local and CI PostgreSQL 17 result) |
| Owner / SECURITY DEFINER / search_path / ACL | `postgres` / yes / `""` / `{postgres=X/postgres}`: unchanged. No client role can execute it |

Repository file to hosted version mapping: the three Phase 2B files were renamed to their hosted versions earlier. F1 keeps the repository name `20261112125000` deliberately: S1 (`20261112130000`) replaces `guard_row()` again, so F1 must sort before it in any ordered replay. Renaming F1 to its hosted version would run it after S1 and overwrite S1's function with the old fix. Hosted applies S1, when approved, will get a later version.

## Preflight (all passed before the write)
1. Project URL matches `uicccaawtjvqggeufbez`.
2. Hosted history was exactly four migrations: `20261112111349`, `20261112115809`, `20261112120132`, `20261112120149`. No S1.
3. `guard_row()` definition, owner, ACL and `search_path` matched the reviewed baseline (md5 above).
4. Defect confirmed by a rollback-only reproduction: `42703: record "new" has no field "project_id"` on UPDATE of `public.projects`.
5. Migration scope: two statements only, `create or replace function nexora_private.guard_row()` and `revoke execute ... from public, anon, authenticated` (a no-op: no client had execute).
6. PostgreSQL 17: suites 29, 57, 43 and the concurrency scenarios green on `e8e12d6` (run 43236184204).
7. All tables empty (0 users, projects, tasks, devices, operations, conflicts); no S1 objects present.
8. Schema drift: columns, constraints, indexes, policies, tables and triggers hash-identical to the local Phase 2B baseline. `acl` differs only by the PostgreSQL 17 `m` (MAINTAIN) bit. Two functions (`nexora_set_updated_at`, `rls_auto_enable`) differ from the local fixture because the fixture reconstructs them; neither is touched.

## Post-apply verification (rollback-only; nothing persisted)
- Catalog before/after: `acl`, `col`, `con`, `idx`, `pol`, `tbl`, `trg` hashes identical; only `guard_row` changed.
- Fix suite `supabase/tests/fix_projects_update_guard_test.sql`: **29/29** (project rename, archive, soft delete, tombstone cannot be reverted, task `project_id` and owner immutable, ownership and anon boundaries, no client DELETE, `guard_row` not executable by clients).
- Phase 2B regression `supabase/tests/rls_and_contract_test.sql`: **57/57**.
- Security Advisor: **no findings**. Performance Advisor: the same 9 INFO items as before (5 unindexed foreign keys, 4 unused indexes); nothing new.
- Persistence check after the tests: 0 rows in every table, `public._ddl_probe` absent. The only residue is `nexora_private.change_seq` at 46 (18 before; sequences are not transactional), which is harmless.

## Recorded original definition and rollback
Original (pre-F1) definition: `supabase/rollback/20261112125000_restore_original_guard_row.sql` (exact text read from hosted). Verified locally: applying it after F1 restores md5 `6deb218e…` and ACL `{postgres=X/postgres}`, and reproduces the defect.

Rollback procedure (needs separate owner approval; it **re-introduces the known defect**, so use it only if F1 causes a worse regression):
1. Confirm project `uicccaawtjvqggeufbez` and read the migration list.
2. Apply the rollback file as a new migration named `nexora_restore_original_guard_row` (forward-only history; do not delete the F1 row from `schema_migrations`).
3. Verify md5 `6deb218ebcdc28a01fda4ec384046f27`, ACL and `search_path`; run the 57-assertion suite rollback-only; confirm no data.
4. Report; project edits stay blocked until F1 is re-applied.
Safe state without rollback: all tables are empty, so a failed fix cannot corrupt user data.
