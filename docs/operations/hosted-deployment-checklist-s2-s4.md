# Hosted deployment checklist for S2, S3 and S4 (prepared, NOT executed)

Status of the slices and gates: `docs/coordination/status-register.md`. This document is a procedure to be performed later. **Nothing in it has been run against the hosted project.** Every step that writes hosted state is marked **[owner approval required]**; read-only steps are marked **[read-only]**. Contract: `docs/architecture/s2-wire-contract.md` and `docs/architecture/s3-s4-wire-contract.md`. Related records: `docs/operations/s1-hosted-deployment-record.md` (the pattern used for S1), `docs/operations/security-hardening-decision-record.md`, `docs/operations/s2-implementation-record.md`, `docs/operations/s3-s4-implementation-record.md`.

## 1. Migration order and file digests
S1 is already applied to the hosted project (hosted version `20261112151851`). The remaining files are applied strictly in this order. Each is a plain SQL file in `supabase/migrations/`; the matching rollback script is in `supabase/rollback/` (rollback scripts are never run by `supabase/tests/run_local.sh` and are not migrations).

| Order | Slice | Migration file | SHA-256 of the migration | Rollback script | SHA-256 of the rollback |
|---|---|---|---|---|---|
| 0 (applied) | S1 | `supabase/migrations/20261112130000_nexora_sync_protocol_schema.sql` | `cb947073bd41166d18a89ac746d94a5b4166a648f4306a3c0d4e0695bc5d42e2` | `supabase/rollback/20261112130000_rollback_s1_sync_protocol_schema.sql` | `97f5e738f96d3a165f1966c9e5beae278ce6a02ffc9a6dda203bc2c7fc538596` |
| 1 | S2 push and register | `supabase/migrations/20261112160000_nexora_sync_push.sql` | `c1361e37450545137e22f9d8a96d224ef35ca9ce6860fc1bcdd62212458a36e9` | `supabase/rollback/20261112160000_rollback_s2_sync_push.sql` | `4cca7211dd1a052becdab0ed40b34829071cc456b166c8c6aa0f611716138404` |
| 2 | S3 resolve, revoke, tree delete | `supabase/migrations/20261112170000_nexora_sync_resolve_revoke.sql` | `b04c1daa01fc933272488e1617e779d1ea7e5020c7b3f3932289c7af3fd7eca8` | `supabase/rollback/20261112170000_rollback_s3_resolve_revoke.sql` | `770a64337ea4f028fc5cd91461446c165c74e00743234f4a4908d8ca3e62f030` |
| 3 | S4 pull and cursor | `supabase/migrations/20261112180000_nexora_sync_pull.sql` | `bcd8dcd49567e4773deaa532e4edab20b53ddceb462bb680711c79b38f76be98` | `supabase/rollback/20261112180000_rollback_s4_sync_pull.sql` | `d514ebc520a697aaacac6f30ab1d4d391767cf53fcff21e9d4b5289b77ac7d62` |

Digests were computed with `sha256sum` on the repository files at the time of writing. Recompute them immediately before applying and compare; stop on any difference. The S3 migration replaces `nexora_private.apply_core` with the S2 text plus the tree-delete path, so S3 must never be applied before S2, and S4 never before S3. Hosted version numbers will be stamped by the platform at apply time and will differ from the file names (as happened for F1 and S1); record both.

## 2. Preflight (all read-only) [read-only]
Run in the SQL editor or through the read-only query tool against the hosted project. Record every result in a new record file (a deployment record in `docs/operations/`, created at deployment time, not now).
1. Project identity matches the expected reference; hosted migration history ends with S1 `20261112151851`; no S2, S3 or S4 object exists.
2. Sync tables are empty: `select count(*) from public.devices`, `public.sync_operations`, `public.sync_conflicts` all return 0. The product tables `projects` and `tasks` may hold rows only if the owner knows about them; S2 does not touch existing rows.
3. Catalog diff: rebuild the expected catalog locally (`supabase/tests/run_local.sh` builds a disposable database from `supabase/tests/00_bootstrap_local.sql` plus every migration) and compare function definitions, ACLs, constraints, triggers and indexes with the hosted catalog, the same way the S1 gate did (`docs/operations/s1-hosted-deployment-gate.md`). Differences other than the known PostgreSQL 17 ACL bit and platform-owned objects stop the deployment.
4. Advisors: run both the security and the performance advisor before and record the baseline, so changes caused by S2 to S4 are visible.
5. Authentication preconditions are recorded (section "Configuration audit checklist for S7" in `docs/operations/auth-dashboard-audit.md`), at least anonymous sign-ins and email confirmation.
6. Direct-write grants and RLS on `projects` and `tasks` are unchanged since the S1 record (they stay until S9; see `docs/operations/s9-direct-grants-removal-plan.md`).

## 3. Apply procedure, one migration at a time **[owner approval required]** for each step
For each of S2, S3, S4 in order:
1. **Dry run in a rollback-only transaction.** Open one transaction, set `lock_timeout` to a few seconds, execute the exact file text, run the verification queries of section 4 in the same transaction, then `rollback`. Nothing persists. Any error stops the procedure.
2. Re-run the dry run with the matching rollback script appended inside the same transaction and compare the catalog snapshot before and after (the same snapshot query used by `supabase/tests/verify_rollbacks.sh`: functions with md5 of definition and ACL, constraints, triggers, columns, indexes, table grants). They must be identical.
3. **Apply for real** with the platform's migration facility, one file per call, copying the file bytes unchanged (digest verified in section 1). Record the stamped version.
4. Run the verification queries (section 4) outside a transaction, then the advisors, and record results. Only then proceed to the next migration.
Do not apply any two migrations in one call. Do not edit a migration file after its digest has been recorded; a change needs a new file and a new review.

## 4. Verification queries [read-only]
After each step (expected values are from the local and PostgreSQL 17 test suites; hosted values are to be recorded, not assumed):
1. **Functions present, owner, security, search_path.** For every function in schemas `public` and `nexora_private` whose name contains `nexora`: owner is `postgres`; the DEFINER functions have `search_path=''` and `lock_timeout=5s` in `proconfig`.
2. **Exact EXECUTE ACL.** Compare with the matrix in `supabase/tests/s2_auth_grants_test.sql`: seven functions in `public` after S4 (`nexora_register_device`, `nexora_resolve_conflict`, `nexora_revoke_device`, `nexora_set_updated_at`, `nexora_sync_pull`, `nexora_sync_push`, `rls_auto_enable`); ten EXECUTE grants for `authenticated` on the new entry points; none for `anon`, `service_role` or `PUBLIC` on any function added by S2 to S4.
3. **Table grants unchanged.** `authenticated` keeps exactly the grants listed in section 2 of `docs/operations/s9-direct-grants-removal-plan.md`; `anon` has none on `public` tables (asserted by `direct_table_grants_unchanged_by_s2_s3_s4` and `anon_has_no_table_grants`).
4. **Constraints and columns.** After S3: `sync_operations_op_type_check` allows `resolve`; `sync_conflicts_status_check` allows `resolved_copy`. After S4: `sync_conflicts.change_seq`, `devices.last_pull_at`, index `sync_conflicts_user_seq_idx`, trigger `sync_conflicts_seq` (enabled always).
5. **Data unchanged.** `devices`, `sync_operations`, `sync_conflicts` still empty after the dry run; `projects` and `tasks` row counts unchanged.
6. **Advisors** show no new finding in comparison with the preflight baseline. A SECURITY DEFINER lint on an exposed schema would indicate that `nexora_private` was exposed (section 6).

## 5. Rollback procedure per migration **[owner approval required]** when run hosted
Always reverse order: S4, then S3, then S2. Each rollback script is verified locally by `supabase/tests/verify_rollbacks.sh` (catalog identical after rollback: 289 catalog lines for S3 to S2 and 284 for S4 to S3 at the time the script was written).
| Step | Script | Behaviour and precondition |
|---|---|---|
| S4 | `supabase/rollback/20261112180000_rollback_s4_sync_pull.sql` | drops `nexora_sync_pull`, `nexora_private.pull`, the trigger and function `guard_conflict_seq`, the index, the column `sync_conflicts.change_seq` and `devices.last_pull_at`. Loses only derived ordering and diagnostic data. |
| S3 | `supabase/rollback/20261112170000_rollback_s3_resolve_revoke.sql` | **aborts with an exception and changes nothing** when any `sync_operations` row has `op_type = 'resolve'` or any `sync_conflicts` row has status `resolved_copy`, because the previous constraints could not hold them. It then drops the resolve and revoke functions and restores the S2 `apply_core`. The abort is the safe outcome; resolving the data conflict is an owner decision (the history is append-only by design). |
| S2 | `supabase/rollback/20261112160000_rollback_s2_sync_push.sql` | drops the S2 functions and the `USAGE` grant on `nexora_private`; no table or data is touched. |
Before any hosted rollback: record the reason, export a copy of `devices`, `sync_operations` and `sync_conflicts` for the record (they hold no secrets), and confirm no client is synchronizing (section 9 kill switches).

## 6. Data API exposed-schema verification **[read-only]** (platform configuration cannot be read through SQL)
The functions in `nexora_private` are SECURITY DEFINER and must never be reachable through the Data API. The exposed-schemas setting is platform configuration.
1. Dashboard: Settings, Data API (API settings): the "Exposed schemas" list contains only `public` (and the platform defaults such as `graphql_public` if present). `nexora_private` must not appear. Record a screenshot description, not the key.
2. HTTP check with the project's anon key only (never the service-role key): `GET <project-url>/rest/v1/rpc/push` with header `Accept-Profile: nexora_private` must be refused (schema not exposed; expect an error status in the 4xx range with a PostgREST error such as PGRST106 for an unexposed profile). `POST <project-url>/rest/v1/rpc/nexora_sync_push` without a user token must be refused (42501 mapped to HTTP 401 or 403). The exact statuses are to be recorded; they are not assumed here.
3. The public wrappers are visible in the OpenAPI document served at `<project-url>/rest/v1/` only as the three RPCs of this slice plus the existing ones; nothing from `nexora_private` is listed.
4. Check `pg_graphql` is still not installed (extension list), as recorded in the security record.

## 7. Hosted HTTP/JWT acceptance **[owner approval required]** (creates a test user and writes test rows)
Purpose: prove the path that no automated test in this repository covers (B-20): PostgREST exposure, real JWT verification, error mapping. Use a dedicated non-production test account created in the dashboard by the owner, with a throw-away password; never a real user. Use only the anon (publishable) key plus the user's access token; the service-role key must not be used. Tests of the same behaviour already run locally against a disposable stack (see the HTTP integration workflow once it exists); the hosted run confirms the hosted configuration only.

Preconditions: sections 2 to 6 passed; auth audit recorded; a second test account exists (for the foreign-user checks); anonymous sign-ins are disabled or, if enabled, an anonymous token is available for the rejection check.

| # | Action (RPC through `POST <url>/rest/v1/rpc/<function>` with `apikey` and `Authorization: Bearer <access token>`) | Expected result |
|---|---|---|
| 1 | Sign in with the test account (password grant) and decode the token header and payload (not the signature): `sub`, `role = authenticated`, `exp`, `is_anonymous` false | token usable |
| 2 | `nexora_register_device` with a new UUID | 200 and `{device_id, created, active_devices}` |
| 3 | `nexora_sync_push` with a create operation for a project | 200, result status `applied`, version 1 |
| 4 | Repeat step 3 with the same `operation_id` | 200, `replayed: true`, no second row |
| 5 | `nexora_sync_pull` with cursor 0 | 200, the project in `changes`, `next_cursor` greater than 0 |
| 6 | Update the same field from a second device with a stale `base_version`, then `nexora_resolve_conflict` with each strategy on separate conflicts | conflict recorded, resolution recorded, evidence unchanged |
| 7 | Anonymous token (if available) or no token on every RPC | refused: SQLSTATE 42501 `anonymous_not_allowed` for anonymous, 28000 `unauthenticated` for a deleted user; HTTP status as returned by PostgREST for these codes (to be recorded) |
| 8 | Second test account calls with the first account's device id, conflict id and entity ids | `device_invalid` (NX001) or `not_found`; no data of the first account in any body |
| 9 | Expired token (wait for expiry or use a token past `exp`) | PostgREST rejects the JWT (error body `PGRST301` family, HTTP 401); the client must refresh and retry |
| 10 | `nexora_revoke_device` of the second device, then any RPC from it | NX001 `device_invalid`; the first device still works |
| 11 | `nexora_sync_pull` with cursor 999999999999 and with -1 | NX006 `invalid_cursor` |
| 12 | Push 101 operations | NX003 `batch_too_large` |
Error mapping reference: `docs/architecture/s3-s4-wire-contract.md` section 5 (28000, 42501, NX001 to NX006 and the transient classes). Record for each call the HTTP status, PostgREST `code`, `message` and the first 200 characters of the body. After the run, remove the test rows through the owner-approved cleanup (history rows are append-only; plan the cleanup as deleting the test users, which cascades as tested, or as part of a rollback-only variant when possible). Record the final state.

## 8. The 8-second statement-timeout measurement **[owner approval required]** for the hosted run
Why: the platform gives the `authenticated` role a statement timeout of 8 seconds (risk R4 and finding 6 in the security and S2 records) and a 100-operation push is one statement. Not measured yet (B-9).
Method, free of `EXPLAIN` (the measurement is wall time, not a plan):
1. Server-side timing inside a rollback-only transaction, so nothing persists: `begin; set local role authenticated; set local statement_timeout = '8s'; select set_config('request.jwt.claims', '<claims of the test user>', true);` register a device, then `select clock_timestamp()` into a variable, run `select public.nexora_sync_push(<device>, <jsonb of N operations>)`, take `clock_timestamp()` again, report the difference; `rollback`. Repeat five times with new operation ids and report minimum, median and maximum.
2. HTTP-level timing with the real path: `curl -sS -o /dev/null -w '%{time_total} %{http_code}\n'` for the same payload through PostgREST (this writes rows: **owner approval required**, and uses the test account).
3. Payload shapes: (a) 100 small operations (about 1 KB each); (b) the client envelope limit of S5, 896 KiB per batch and 224 KiB per operation; (c) the server worst case, 100 operations whose patches approach the 262,144-byte server limit (the server limit, not a realistic client batch); (d) one tree delete with a 1000-entry manifest on a tree of 1000 tasks; (e) a pull of 500 rows and of the 1 MiB byte bound. Run (c) only in the rollback-only variant.
4. Pass criteria (recommendation, to be confirmed by the owner): (a), (b), (d), (e) finish in under 4 seconds at the maximum of five runs (a 2x margin); (c) is informational. A statement timeout (SQLSTATE 57014) is a failure.
5. On failure: record the shape that failed; propose lowering the batch limit (a contract change affecting S2 and S5, NX003 threshold), splitting the tree delete bound, or lowering the pull byte bound; do not change the platform timeout without a separate decision. Update `docs/architecture/s3-s4-wire-contract.md` and the register only after approval.

## 9. Production activation and rollback checklist **[owner approval required]** (none of it is authorized today)
Activation prerequisites (all must be true and recorded):
- Hosted S2, S3 and S4 applied and verified (sections 3 to 6); hosted HTTP/JWT acceptance passed (section 7); statement-timeout measurement within criteria (section 8).
- Authentication audit recorded and accepted (anonymous sign-ins, email confirmation, JWT expiry, refresh-token rotation; `docs/operations/auth-dashboard-audit.md`).
- Owner decisions taken: O-1 (`completed_at`), O-2 (response size), O-3 (rate limit and retention, see `docs/operations/rate-limit-and-log-retention-recommendations.md`), O-6 (privilege model), S9 timing (`docs/operations/s9-direct-grants-removal-plan.md`).
- Device cap: ten active devices per user; the revoke RPC exists (S3), the client exposes revocation; support procedure for a locked-out user written.
- Monitoring in place before the first real user: Supabase logs for the three RPCs (rate of NX001, NX003, NX006 and 5xx), `sync_operations` growth, advisor re-run weekly, an owner-readable dashboard query for open conflicts older than seven days.
- Build: a release built with `--dart-define=NEXORA_SYNC=true` plus the project URL and the **anon** key supplied at build time (never the service-role key; never committed). The default build stays OFF.
- Kill switches (any one is sufficient): (1) ship or roll back to a build without `NEXORA_SYNC`; (2) revoke all devices of a user with `nexora_revoke_device` (clients then pause as "device removed", keep their data); (3) revoke `EXECUTE` on the three client-facing RPCs from `authenticated` (reversible `REVOKE`; clients see 42501 and stop; pending work stays on the devices); (4) disable sign-in in the Auth dashboard.
Rollback of an activation: disable the flag build and publish it; revoke devices if needed; confirm no RPC traffic in the logs for 24 hours; then, only if required, run the SQL rollbacks in the order S4, S3, S2 (section 5). Local SQLite data is never touched by any of these steps; operations that were pending stay pending on the device.
