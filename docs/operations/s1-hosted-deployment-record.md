# S1 hosted deployment record and S2 entry report (2026-11-12)

**Note (2026-11-14): this record describes the state at the time it was written. Statements such as "not applied to hosted", "disabled" or "not run" are historical; the hosted TEST deployment and Phase 3 acceptance are recorded in `docs/operations/hosted-acceptance-record-2026-11-13.md` and the current status is in `docs/coordination/status-register.md`.**

Target: Supabase project `uicccaawtjvqggeufbez` (PostgreSQL 17.11). Authorization: owner, for the S1 protocol-schema migration only, conditional on a rollback-only dry run and exact-state preflight. **Not authorized and not done:** RPC activation, authentication activation, synchronization, direct-write permission changes, sharing, merging Phase 3 into `main`.

## Result
| Item | Value |
|---|---|
| Hosted migration | `20261112151851_nexora_sync_protocol_schema`, recorded exactly once; history is now six migrations |
| Repository file | `supabase/migrations/20261112130000_nexora_sync_protocol_schema.sql` (name kept so it sorts after F1 `20261112125000`) |
| SQL SHA-256 | `cb947073bd41166d18a89ac746d94a5b4166a648f4306a3c0d4e0695bc5d42e2` (approved value matched) |
| Rollback SHA-256 | `97f5e738f96d3a165f1966c9e5beae278ce6a02ffc9a6dda203bc2c7fc538596` (approved value matched; script **not** executed) |
| Reviewed HEAD | `c1396550e6705771670b8a480fe765793f7840f2` |
| `guard_row()` md5 | before `305edd2eb7769b45807eac9b07287876` (F1), after `c8a7bfc37dec9d0b10a19a8ba475d3c6` (the expected S1 hash) |

## Gate 1: exact-state preflight (all passed)
Correct project URL; history exactly the five expected migrations ending in `20261112142732`; `guard_row()` equal to the verified F1 version (owner `postgres`, SECURITY DEFINER, `search_path=""`, ACL `{postgres=X/postgres}`); every table empty; zero S1 columns, functions, triggers or indexes present; guard triggers in default mode; device FK `RESTRICT`; all eight catalog category hashes identical to the post-F1 values (no drift); both file hashes matched the approved values; the S1 blob is identical to the commit tested by PostgreSQL 17 CI run 43236184204 and later runs.

## Gate 2: hosted rollback-only dry run (passed)
The unmodified S1 file was executed inside a DO block that gathered checks and then unconditionally raised, so it could not commit. Inside the transaction: all statements succeeded; 7 columns, 6 indexes, 8 constraints, 4 new functions and 5 new triggers existed; the three Phase 2B guard triggers and the three new guards were `ENABLE ALWAYS`; the device FK was `NO ACTION`; `guard_row()` md5 was `c8a7bfc3…`; the `acl`, `pol` and `tbl` hashes equaled the pre-state; `public` still had only its two existing functions; no client role could execute any `nexora_private` function. After the block: all eight hashes were back to the pre-state, history unchanged (five), no S1 objects, 0 rows, `change_seq` unchanged at 46. Nothing was recorded as a migration.

## Gate 3: applied once
Applied through the migration workflow with the exact file text; recorded once as `20261112151851`.

## Gate 4: verification (rollback-only; nothing persisted)
- Live catalog equals the dry run's in-transaction state for every category: `fn` 8 (`4fef8485…`), `col` 77, `con` 45, `idx` 24, `trg` 11; `acl`, `pol`, `tbl` unchanged.
- Suites on hosted: **S1 43/43**, **F1 29/29**, **Phase 2B regression 57/57**.
- Trigger modes: `projects_guard`, `tasks_guard`, `tasks_guard_cycle`, `devices_guard`, `sync_operations_append_only`, `sync_conflicts_guard` = `A` (always); the two `*_no_truncate` = `O`.
- Client privileges unchanged: `authenticated` has SELECT on `devices`, `sync_operations`, `sync_conflicts`; INSERT/SELECT/UPDATE on `profiles`, `projects`, `tasks`; no DELETE; `anon` has no table grant. 16 policies, every table has RLS. No new client EXECUTE on any `nexora_private` function (0). `public` functions: `nexora_set_updated_at()`, `rls_auto_enable()` only (0 client-callable RPC, 0 sync functions).
- Security Advisor: **no findings**. Performance Advisor: the five unindexed-foreign-key INFO items from before are resolved by S1's indexes; INFO "unused index" now lists four existing indexes plus the new `tasks_parent_fk_idx` (expected with empty tables).
- Final data state: 0 users, profiles, projects, tasks, members, devices, operations and conflicts; `public._ddl_probe` absent.
- Sequence: `nexora_private.change_seq` is 82 (46 before the verification suites). Sequences are not transactional, so rollback-only runs consume values. Gaps do not affect correctness: the pull cursor needs only monotonic, commit-ordered values per user, not contiguous ones.
- Synchronization remains disabled: no RPC exists, clients have no write grant on the sync tables, no direct-write grant changed.

## Recovery (not executed)
`supabase/rollback/20261112130000_rollback_s1_sync_protocol_schema.sql` restores the post-F1 catalog exactly (verified locally) and aborts if any sync row or field version exists. Use needs separate owner authorization.

## S2 development entry report
**Readiness: GO for local-only S2 development** under the approved design (`docs/superpowers/plans/2026-11-12-nexora-phase-3-s2-push-rpc.md`). The plan's prerequisite, S1 applied and verified on hosted, is now met. S2 may be built and tested on disposable PostgreSQL (local and the PostgreSQL 17 CI). **S2 must not be deployed or exposed**, and no authentication, sync or sharing is enabled.

Outstanding blockers and decisions before any S2 hosted step:
1. Separate owner approval to start S2, plus the error taxonomy and limits proposed in the S2 plan.
2. D-U (anonymous sign-in and public sign-up) audit: required before any authentication or synchronization activation. S2 rejects anonymous JWTs regardless.
3. Direct INSERT/UPDATE on `projects` and `tasks` stays granted until the S9 activation gate; those paths bypass conflict detection. The per-user lock now covers them on hosted.
4. Fidelity of the test environment: the PostgreSQL 17 CI uses stub Supabase roles, not the Supabase image; S2's JWT-claim handling (`auth.uid()`, `is_anonymous`) should be tested with claim fixtures and re-verified rollback-only on hosted.
5. Client side: Phase 3 S5 (outbox v2) is not started; S6 depends on it.
6. ~~Documentation on `main` still describes S1 as not applied~~ Corrected on the development branch by the 2026-11-12 documentation consolidation (status: `docs/coordination/status-register.md`); reaching `main` needs a separate owner-approved merge. The S1 SQL and tests exist only on `claude/affectionate-turing-unzmd2` until then.
