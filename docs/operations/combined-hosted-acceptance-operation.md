# Combined hosted acceptance operation (prepared, NOT executed)

**Status update (2026-11-14): this operation was executed on the hosted TEST project on 2026-11-13; the result is in `docs/operations/hosted-acceptance-record-2026-11-13.md`. The text below is the original runbook and is kept for history and for any rollback.**

Status: **prepared only.** Nothing in this document has been run against the hosted project. Every hosted write needs the owner's explicit authorization of this operation; until then only the read-only steps marked **[read-only]** may be performed. Related documents: `docs/operations/hosted-deployment-checklist-s2-s4.md` (detailed procedure and verification queries for S2 to S4), `docs/operations/s9-direct-grants-removal-plan.md`, `docs/operations/hardening-implementation-record.md`, `docs/operations/hosted-readonly-preflight-2026-11-12.md`, `docs/operations/auth-dashboard-audit.md`.

Hosted project reference `uicccaawtjvqggeufbez`, PostgreSQL 17. Hosted state at preparation (read-only, 2026-11-12): six migrations applied (up to S1 `20261112151851`), no sync objects beyond S1, `auth.users` 0 rows, `projects` and `tasks` 0 rows, `authenticated` has `statement_timeout=8s` and the direct grants `arw` on `projects`, `tasks` and `profiles`.

## 1. What "one controlled operation" means
One authorized session with eight internal checkpoints (section 3). Each checkpoint has an exit criterion. **Any failed criterion stops the operation** (section 5): nothing later is run, the failing step is rolled back if it changed state, and the operator writes the execution record. The operation never continues past a failure "to see what else happens".

## 2. Migration files and digests
Apply strictly in this order, one file per call, copying the file bytes unchanged. Recompute `sha256sum` immediately before applying and compare with this table; stop on any difference. S3 never before S2, S4 never before S3, the throttle and response bound never before S4, S9 last. Hosted version numbers are stamped by the platform and differ from the file names; record both.

| Step | Slice | Migration | SHA-256 | Rollback | SHA-256 |
|---|---|---|---|---|---|
| 1 | S2 push and register | `supabase/migrations/20261112160000_nexora_sync_push.sql` | `c1361e37450545137e22f9d8a96d224ef35ca9ce6860fc1bcdd62212458a36e9` | `supabase/rollback/20261112160000_rollback_s2_sync_push.sql` | `4cca7211dd1a052becdab0ed40b34829071cc456b166c8c6aa0f611716138404` |
| 2 | S3 resolve, revoke, tree delete | `supabase/migrations/20261112170000_nexora_sync_resolve_revoke.sql` | `b04c1daa01fc933272488e1617e779d1ea7e5020c7b3f3932289c7af3fd7eca8` | `supabase/rollback/20261112170000_rollback_s3_resolve_revoke.sql` | `770a64337ea4f028fc5cd91461446c165c74e00743234f4a4908d8ca3e62f030` |
| 3 | S4 pull and cursor | `supabase/migrations/20261112180000_nexora_sync_pull.sql` | `bcd8dcd49567e4773deaa532e4edab20b53ddceb462bb680711c79b38f76be98` | `supabase/rollback/20261112180000_rollback_s4_sync_pull.sql` | `d514ebc520a697aaacac6f30ab1d4d391767cf53fcff21e9d4b5289b77ac7d62` |
| 4 | S10a per-user throttle (NX007) | `supabase/migrations/20261112185000_nexora_sync_throttle.sql` | `bddbd3cd9defb28a23e4b74fa9c1c53e11ee89325d5f5ec564174bee83df6936` | `supabase/rollback/20261112185000_rollback_sync_throttle.sql` | `455e988838a8b1f393dfca244eade9dcba042fb0492f1f57dcbd0bb82c6c8eec` |
| 5 | S10b push response bound | `supabase/migrations/20261112186000_nexora_sync_response_bound.sql` | `9734ac8add8dbecd1d80d2db8fd0c81a0d81745e58d9dc48bd416b0b2d5653d5` | `supabase/rollback/20261112186000_rollback_sync_response_bound.sql` | `afbe73109bf94f91ca688fded152dc04d4ab8236808f45e002c8f49e087242f0` |
| 7 | S9 direct-write revoke | `supabase/migrations/20261112190000_nexora_s9_revoke_direct_writes.sql` | `42086e9a0603fc9def9c582251f35657a54f7365de37fa0a3940dc571766e34c` | `supabase/rollback/20261112190000_rollback_s9_direct_writes.sql` | `417a61922699df5851b4e2c0da42b4895358cca3b8c1e61994e2a2811901a9b2` |

S1 (`20261112130000`, hosted `20261112151851`) is already applied; its digests are in the checklist. Local evidence: `supabase/tests/run_local.sh` (all suites on a disposable database, S9 applied after the legacy direct-write suites), `supabase/tests/verify_rollbacks.sh` (each rollback restores the previous catalog exactly; S9 forward and rollback are idempotent), `supabase/tests/mutation_checks.sh` (52 mutations caught, 0 missed), the `supabase-schema-tests` workflow on PostgreSQL 17 and the `http-integration` workflow (real PostgREST and GoTrue; S9 refusal asserted over HTTP).

## 3. Ordered operation with checkpoints
| # | Checkpoint | Writes hosted state | Exit criterion (all must hold) |
|---|---|---|---|
| 1 | **Read-only preflight and configuration audit** [read-only] | no | Section 4.1 queries return the recorded baseline (six migrations, empty sync tables, ACL baseline); security advisor baseline recorded; Auth audit table filled (settings that cannot be read stay UNVERIFIED and are decided by the owner before step 5); Data API exposed schemas do not contain `nexora_private`. |
| 2 | **S2** dry run in a rolled-back transaction, then apply, then verify | yes | Dry run clean; catalog identical after dry run plus rollback; applied digest equals table; checklist section 4 queries pass; no new advisor finding. |
| 3 | **S3** same pattern | yes | Same, plus `resolve` allowed by the constraints. |
| 4 | **S4** same pattern | yes | Same, plus `change_seq`, `last_pull_at`, trigger present. |
| 4b | **Throttle and response bound** (steps 4 and 5 of the table) same pattern, one file per call | yes | Section 4.3 queries pass: `rate_policy` rows present with defaults, `nexora_private.rate_bucket` empty, the response-bound function present; no new advisor finding. |
| 5 | **Hosted HTTP/JWT acceptance** with a dedicated synthetic account | yes (test rows only) | Section 4.4: registration, push, pull, conflict, resolve and revoke succeed over HTTPS with the user's JWT; anonymous and cross-account calls are refused; the NX007 throttle answers a burst with `rate_limited` and the account recovers after the window. The synthetic account and its rows are removed or kept only on the owner's instruction. |
| 6 | **Hosted timeout and response-size measurements** | yes (test rows only) | Section 4.5: 100-operation push, 500-row pull page and 1,000-descendant tree delete complete well under the 8 s role timeout; measured response sizes within the ceilings of `supabase/tests/measure_limits.sh` (largest accepted push response about 2 MB). Record the numbers. |
| 7 | **S9** direct-write revoke, then verify | yes | Direct INSERT, UPDATE and DELETE on `projects` and `tasks` by `authenticated` are refused over HTTPS (`project_members` has no client grants at all); SELECT still works; the RPC path of step 5 is re-run and still passes. **`profiles` is deliberately NOT restricted by S9**: it keeps `arw` for `authenticated` (intended permission; asserting that profile writes are refused would be a runbook error, corrected 2026-11-13). |
| 8 | **Final hosted security and performance advisor review** [read-only] | no | No new advisor finding compared with the step 1 baseline; any finding is recorded and either explained or turned into a blocker. |

Activation of synchronization for real users is **not** part of this operation (section 7).

## 4. Executable verification queries
All are read-only (`select` only). Run them in the SQL editor or through the read-only query tool. Record the output in the execution record; expected values come from the local and CI suites and hosted values are recorded, not assumed.

### 4.1 Preflight baseline [read-only]
```sql
select version from supabase_migrations.schema_migrations order by version;           -- 6 rows, last 20261112151851
select (select count(*) from public.devices) d, (select count(*) from public.sync_operations) o,
       (select count(*) from public.sync_conflicts) c, (select count(*) from auth.users) u,
       (select count(*) from public.projects) p, (select count(*) from public.tasks) t;
select rolconfig from pg_roles where rolname = 'authenticated';                       -- {statement_timeout=8s}
select relname, relacl::text from pg_class
 where relnamespace = 'public'::regnamespace and relname in ('projects','tasks','profiles') order by 1;
select proname from pg_proc where pronamespace in ('public'::regnamespace, 'nexora_private'::regnamespace)
 and proname like any (array['%nexora%','push','pull','apply_%']) order by 1;       -- S1 objects only
select count(*) from pg_extension where extname = 'pg_graphql';                      -- 0 expected
```
Also record the security and performance advisors (baseline: security advisor empty on 2026-11-12) and the Data API exposed schemas (Dashboard, Settings, Data API).

### 4.2 After each of S2, S3, S4
Use section 4 of `docs/operations/hosted-deployment-checklist-s2-s4.md` unchanged (functions, owners, `search_path`, exact EXECUTE ACL, table grants, constraints, data unchanged, advisors).

### 4.3 After the throttle and response bound
```sql
select * from nexora_private.rate_policy order by 1;                 -- 120 pull calls, 120 write calls, 6000 operations per minute
select count(*) from nexora_private.rate_bucket;                    -- 0 before the acceptance run
select proname, prosecdef, proconfig from pg_proc
 where pronamespace = 'nexora_private'::regnamespace order by 1;      -- DEFINER functions: search_path='' and lock_timeout=5s
select has_function_privilege('authenticated','public.nexora_sync_push(uuid, jsonb)','execute') as push_ok,
       has_function_privilege('anon','public.nexora_sync_push(uuid, jsonb)','execute') as anon_push;   -- true / false
```

### 4.4 Hosted HTTP/JWT acceptance (writes test rows)
Use the publishable (anon) key plus the synthetic account's access token only; **never the service-role key**. Dedicated synthetic account created by the owner in the dashboard with a throw-away password. Steps and expected results are those of section 7 of the checklist, extended with: (a) a burst of pull calls above the policy answers `rate_limited` (SQLSTATE NX007, HTTP 4xx with that message) and the next window succeeds; (b) an oversized push batch answers `payload_too_large` (NX004) and halving succeeds; (c) an anonymous JWT is refused (`anonymous_not_allowed`).

### 4.5 Timeout and size measurements
Use the same synthetic account. Measure with the client's own HTTP stack or `curl` timing: a 100-operation push with realistic payloads, a 500-row pull page, a 1,000-descendant tree delete. Record wall time, response bytes and the HTTP status. Compare with the local numbers in `docs/operations/hardening-implementation-record.md`. Anything near 8 s is a stop.

### 4.6 After S9 [read-only] plus HTTP
```sql
select relname, relacl::text from pg_class
 where relnamespace = 'public'::regnamespace and relname in ('projects','tasks','profiles') order by 1;
-- expected: authenticated retains only SELECT (r) on projects and tasks; profiles keeps its existing privileges as designed in the S9 plan
select polname, polcmd from pg_policy where polrelid in ('public.projects'::regclass,'public.tasks'::regclass,'public.profiles'::regclass) order by 1;
```
Then over HTTPS with the synthetic account: INSERT, UPDATE and DELETE on `projects` and `tasks` are refused (401 or 403); SELECT works; RPC push, pull, resolve and revoke still work.

## 5. Stop-on-failure procedure
1. At the first failed exit criterion, **stop**. Do not run another checkpoint.
2. Record the failure (query, output, time) in the execution record (section 8).
3. **Stop and preserve state when a rollback is not possible or not safe** (section 5a), otherwise roll back only what this operation changed, in reverse order, using the rollback scripts of section 2 (S9, response bound, throttle, S4, S3, S2). Each rollback is verified locally; S3's rollback **aborts without changes** if resolve operations exist (the safe outcome; the owner decides). Before any rollback copy the contents of `devices`, `sync_operations`, `sync_conflicts` (no secrets) into the record.
4. Re-run section 4.1 to show the hosted state returned to the baseline (or document the difference).
5. Remove the synthetic account only on the owner's instruction. Keep `NEXORA_SYNC` off.
6. Fix forward locally, rerun every suite on a disposable database, and ask for a new authorization; a changed migration gets a new file, a new digest and a new review.

### 5a. Stop-and-preserve-state procedure (corrected 2026-11-13)
Not every hosted change can be undone. `sync_operations` and `sync_conflicts` are append-only by design, so once an immutable `resolve` operation or a `resolved_copy` conflict exists, **the S3 rollback aborts without changing anything** (its guard raises an exception; this is the safe outcome, not a failure of the script). Therefore:
1. Do not force the rollback, do not delete or edit history rows and do not alter a migration to make it pass.
2. **Stop further hosted writes.** Keep the schema as it is; a server that has S3 applied is a valid, tested state.
3. **Preserve state:** copy the contents of `devices`, `sync_operations`, `sync_conflicts` (no secrets) and the migration history into the execution record; note the row counts per table.
4. Switch off the clients (kill switch, section 6, client level) and, if needed, revoke `EXECUTE` on the entry points from `authenticated` (section 6, grants level). Both are reversible and lose nothing.
5. Report the blocker. The owner decides between fixing forward with a new reviewed migration or an explicit data decision; the rollback may be retried only after the data question is resolved.
Rollbacks that remain possible with data present: S9 (grants only), response bound and throttle (function replacement; the throttle also drops `rate_bucket` rows, which are disposable counters), S4 (drops derived ordering and diagnostic columns).

## 6. Rollback and kill switch (after the operation, during pilot use)
| Level | Action | Effect | Data impact |
|---|---|---|---|
| Client | Ship or run the build without `--dart-define=NEXORA_SYNC=true` (the default build never contacts the server) | Desktop app returns to local only; pending outbox rows stay in the account database file | none |
| Account | Revoke the device (`nexora_revoke_device`) or delete the user in the dashboard | The device or user can no longer push or pull | server rows remain; local data remains |
| Server, throttle | Lower the `rate_policy` values (owner-approved write) | Slows or blocks one class of calls | none |
| Server, grants | Revoke `EXECUTE` on `nexora_sync_push`, `nexora_sync_pull`, `nexora_resolve_conflict` from `authenticated` | Every client gets a refusal and backs off; nothing is lost locally | none |
| Server, S9 | Run the S9 rollback only if a legitimate direct-write need is demonstrated | Restores `arw` | reopens the bypass the RPCs were built to prevent |
| Schema | Rollback scripts in reverse order (section 5) | Restores the earlier catalog | derived and diagnostic data only |

## 7. Activation is separate
After a successful operation, enabling synchronization for the owner's own account needs: the Auth decisions of `auth-dashboard-audit.md` (public sign-up off, JWT expiry, rate limits), a release build with `NEXORA_SYNC=true` and the project settings supplied at build time, the release acceptance checklist, and a separate explicit owner authorization.

## 8. Execution record template
Copy this block into a new file `docs/operations/hosted-acceptance-record-<date>.md` at execution time.
```
Operation authorized by: ______  at (UTC): ______  Operator: ______
Branch / head: ______  CI run ids at that head: ______
Hosted project: ______  Baseline (4.1): migrations ______  sync tables ______  ACL ______  advisors ______
Step 1 preflight        result: ______  exit criterion met: yes/no
Step 2 S2   digest ______  hosted version ______  dry run ______  verify ______  advisors ______
Step 3 S3   digest ______  hosted version ______  dry run ______  verify ______  advisors ______
Step 4 S4   digest ______  hosted version ______  dry run ______  verify ______  advisors ______
Step 4b throttle digest ______ version ______ / response bound digest ______ version ______  verify ______
Step 5 HTTP/JWT acceptance (synthetic account id ______)  results ______
Step 6 timing: push-100 ______ ms ______ bytes; pull-500 ______ ms ______ bytes; tree-delete-1000 ______ ms
Step 7 S9   digest ______  hosted version ______  direct write refused: INSERT ____ UPDATE ____ DELETE ____  RPC path ______
Step 8 final advisors: security ______ performance ______
Stopped at step: ______  Rollback performed: ______  Hosted state after: ______
Synthetic account disposition: ______   NEXORA_SYNC remains off: yes/no
```
