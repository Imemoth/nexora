# S1 hosted deployment gate report (prepared 2026-11-12; S1 NOT applied)

Migration: `supabase/migrations/20261112130000_nexora_sync_protocol_schema.sql`, SHA-256 `cb947073bd41166d18a89ac746d94a5b4166a648f4306a3c0d4e0695bc5d42e2`.
Rollback (verified locally): `supabase/rollback/20261112130000_rollback_s1_sync_protocol_schema.sql`, SHA-256 `97f5e738f96d3a165f1966c9e5beae278ce6a02ffc9a6dda203bc2c7fc538596`.
Baseline reviewed against: hosted after F1 (`20261112142732`), `guard_row()` md5 `305edd2eb7769b45807eac9b07287876`.

## Verdict: technically GO, deployment needs a separate owner approval
Nothing here applies S1, enables synchronization, changes direct-write grants, RLS, Auth or sharing.

## 1. Is S1 still additive and safe against the hosted baseline?
Catalog diff of "hosted baseline + F1" versus "+ S1" (rebuilt locally from the same migrations; the hosted catalog matched that baseline except for the PostgreSQL 17 `m` ACL bit and two fixture functions, see `f1-hosted-fix-record.md`):
| Change | Count | Notes |
|---|---|---|
| Columns added | 7 | `projects.field_versions`, `tasks.field_versions`, `devices.last_push_at`, `sync_conflicts.kind`, `resolution_source`, `resolution_policy`, `resolution_operation_id` |
| Constraints added | 8 | two `field_versions` object checks; on `sync_conflicts`: `kind`, `resolution_source`, `resolution_policy`, `resolution_consistent`, `policy_only_auto` checks and the `resolution_operation_id` foreign key; all on empty tables |
| Functions added | 4 | `user_lock_key`, `lock_user`, `guard_sync_log`, `guard_device`, all in `nexora_private` |
| Function replaced | 1 | `guard_row()` (superset of F1: keeps the nested fix, adds the user lock and `field_versions`) |
| Constraint replaced | 1 (the 9th changed constraint line in the raw catalog diff) | `sync_operations_device_id_user_id_fkey`: `ON DELETE RESTRICT` becomes `NO ACTION` (so deleting a user can cascade; tested) |
| Triggers added | 5 | append-only and no-truncate guards, device guard; three Phase 2B guard triggers become `ENABLE ALWAYS` |
| Indexes added | 6 | foreign-key coverage |
| **Grants, RLS policies, table privileges, schema ACL** | **0 changed** | none |
| **New functions in `public` (Data API RPC)** | **0** | |
Statement inventory: no table drop, no `DELETE`/`UPDATE`/`TRUNCATE`, no `GRANT`; one constraint drop (re-added). S1 aborts with an exception if `sync_conflicts`, `sync_operations` or `devices` holds a row (all empty on hosted at preflight).

## 2. Permissions, SECURITY DEFINER, search_path
| Function | SECURITY DEFINER | search_path | EXECUTE |
|---|---|---|---|
| `nexora_private.guard_row()` | yes | `""` | `postgres` only |
| `nexora_private.guard_device()` | yes | `""` | `postgres` only |
| `nexora_private.guard_sync_log()` | no | `""` | `postgres` only |
| `nexora_private.lock_user(uuid)` / `user_lock_key(uuid)` | no | `""` | `postgres` only |
Client calls to the private functions fail with 42501 (tested). A forged `owner_id` is rejected before any lock is taken. Expected Security Advisor result after apply: no findings (no `public` function, no exposure change).

## 3. Advisory-lock discipline and commit-ordered pull
- The lock (`pg_advisory_xact_lock` on a hash of `owner_id`) is taken inside the guard trigger before `nextval`, on every write path (authenticated, service_role, postgres). Triggers are `ENABLE ALWAYS`, so `session_replication_role = replica` cannot bypass them. A catalog coverage test asserts that every table with `change_seq` has an always-enabled guard.
- Multi-session proof on PostgreSQL 17 (CI): scenario A (lock in place) loses nothing; scenario B (negative control, lock removed) loses a row; scenario C (forged owner) fails in about 30 ms without taking the victim's lock.
- Transaction-level advisory locks are safe behind a transaction pooler (they release at transaction end), and each Data API request is one transaction.

## 4. field_versions, conflict audit, device cap
Tests in `s1_sync_schema_test.sql` (43 assertions): per-field versions are server-owned and unforgeable; conflict kinds are constrained; `resolution_source`/`resolution_policy` are consistent (the only policy is `sort_order_server_wins`); preserved values are immutable and resolved conflicts are final; `sync_operations` is append-only; deleting a user still cascades; the 11th active device is rejected (54000), a revoke frees a slot, un-revoking beyond the cap is rejected.

## 5. S1 composes with F1
`guard_row()` in S1 contains the F1 nested check. The F1 suite (29), Phase 2B regression (57) and S1 suite (43) all pass on the chain F1 then S1 (local PostgreSQL 16 and PostgreSQL 17 CI: runs 43225149883, 43236184204). Security contract unchanged: same grants and policies, same client privileges.

## 6. Verification evidence
- PostgreSQL 17.11 CI on the merged HEAD `e8e12d6`: [run 43236184204](https://github.com/Imemoth/nexora/actions/runs/43236184204) success (29, 57, 43, concurrency A/B/C).
- Rollback proof: applying the rollback after S1 restores the catalog to the F1 state exactly (169 lines, empty diff) and the 29/57 suites pass again; it aborts when a sync table has rows.

## 7. Deployment gates (all required, in order)
1. Separate written owner approval to apply S1 to `uicccaawtjvqggeufbez`.
2. Preflight: project URL; migration history is exactly the five known migrations ending in `20261112142732`; `guard_row()` md5 `305edd2e…`; all tables empty; no S1 objects; no unexpected schema drift.
3. Optional but recommended, needs explicit OK: a hosted **rollback-only dry run** (DDL inside a block that always raises) to validate privileges and event triggers on the real project before the real apply. I did not run it.
4. Apply the exact file once; confirm it is recorded once.
5. Verify: catalog diff equals the table in section 1; `guard_row()` md5 equals the expected S1 hash `c8a7bfc37dec9d0b10a19a8ba475d3c6` (computed locally; F1's equivalent hash was identical on local PostgreSQL 16, PostgreSQL 17 CI and hosted); rollback-only 29, 57, 43; Security and Performance Advisors; no persistent rows.
6. Stop conditions (no further writes, report): any gate mismatch, failed assertion, new Advisor finding, or non-empty sync table. Recovery: the rollback script (needs approval).

## 8. Remaining risks and owner decisions
- **D-U** (anonymous sign-in, public sign-up) is still unaudited; required before any authentication or synchronization activation, not before S1.
- Direct INSERT/UPDATE on `projects` and `tasks` remains granted until the S9 activation gate; the lock covers those paths, but they bypass conflict detection. Synchronization is disabled, so no client uses them for sync.
- The PostgreSQL 17 CI uses stub Supabase roles, not the Supabase image; the hosted rollback-only suites are the real-environment check.
- The append-only guard uses `pg_trigger_depth()`; grants (no client DML on the sync tables) are the actual boundary.
- Decision needed: approve S1 deployment, and whether to run the hosted rollback-only dry run first.
