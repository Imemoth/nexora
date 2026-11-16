# Due time: hosted migration request (prepared, NOT applied)

> **Policy:** Nexora is DEVELOPMENT/TEST only; no production exists; the Supabase project is DEV/TEST with mock data. Production-style rollback, release and compatibility parts below are optional guidance, not requirements; hosted writes still need the owner's separate authorization. See [`docs/development-environment-policy.md`](../development-environment-policy.md).

Status: **prepared only. Nothing in this document has been run against the hosted project.** The hosted project is `uicccaawtjvqggeufbez` (the TEST project). Applying the migration, or any other hosted write, needs the owner's explicit authorization of **this exact operation**. Read-only steps are marked **[read-only]**. Decision record: `docs/architecture/decisions/0004-due-time-semantics-and-hosted-boundary.md`. Pattern and stop rules follow `combined-hosted-acceptance-operation.md` (sections 1 to 6).

## 1. What is requested
One additive migration, one rollback, no data written, no grant, policy, index or cursor changed, no Auth setting changed.

| File | SHA-256 (verify immediately before applying) |
|---|---|
| `supabase/migrations/20261116100000_nexora_due_time.sql` | `71ebd1de87cb5d95bca0fddf99b2a8401b26d6946f8ca913a4e8d9570c59263e` |
| `supabase/rollback/20261116100000_rollback_due_time.sql` | `092fde7697ede0c2bc79ed357d8262af42f2778afe8190a9a70931044d203edf` |

A changed file means a new review and new digests. Hosted migration name proposed: `nexora_due_time`.

### What the migration does
1. `public.tasks.due_time time without time zone null` and the check `tasks_due_time_needs_date` (a time needs a date; no seconds; below 24:00). Every existing row gets NULL: date-only stays date-only. No table rewrite beyond the metadata change of an added nullable column.
2. Replaces `nexora_private.guard_row` (adds `due_time` to the tracked fields, so it has a `field_versions` entry and takes part in conflict detection), `nexora_private.patch_spec` (the patch key `due_time`: string or null), `nexora_private.apply_core` and `nexora_private.resolve_core` (see 3), and `nexora_private.register_device` (answers `"features": ["due_time"]`).
3. Adds `nexora_private.pair_due_time` (pure helper, no client EXECUTE). **Older clients:** when a patch changes `due_date` and does not mention `due_time`, and the task has a time, the time is cleared in the same update. A stale time can never survive a date change made by a client that does not know the time. Applies to push (`apply_core`) and to conflict resolution (`resolve_core`, including `recreate_copy`).
4. Function ACLs are re-asserted exactly as before (`revoke ... from public, anon, authenticated` for the private functions). `register_device` keeps its grant (replacing a function keeps its owner and ACL; the verification below checks it).

### What it does not do
Does not touch `projects`, `devices`, `sync_operations`, `sync_conflicts`, the pull cursor, RLS policies, table grants (S9 stays as is: direct writes remain refused), the throttle, the response bound, Auth settings, or any secret. The wire contract gains one optional field; every existing field and error code is unchanged.

## 2. Local evidence already produced (disposable PostgreSQL 16 on the development machine; CI uses 17)
| Evidence | Result |
|---|---|
| `supabase/tests/run_local.sh` (all existing suites plus `due_time_test.sql`, S9 applied last) | `ALL SUITES PASSED`; the due-time suite has 47 assertions |
| `supabase/tests/verify_due_time_migration.sh` | existing rows byte-identical after the migration; no row lost; no time appears; the rollback restores the catalog **exactly** (329 catalog lines: functions, constraints, triggers, columns, indexes, ACLs, policies, grants); re-applying after a rollback gives the same catalog; rolling back with stored times keeps every date and drops only the times |
| Two-device end-to-end against the migrated server (`test/e2e/due_time_sync_test.dart`, 17 tests) | create, edit, clear, move the date with and without a time, offline retry with fold and restart, conflicts and all four resolution strategies on the time, an older client changing or clearing the date (patches without `due_time`), capability detection and its loss, local-to-account import with and without server support |
| Existing e2e (`test/e2e/two_device_sync_test.dart`) | unchanged and passing on the migrated schema |
| PostgREST, JWT verification, the platform `statement_timeout` | **not exercised locally**: same limitation as the earlier hosted gate; the hosted HTTP check in section 4.4 covers it |

## 3. Deployment sequence (needs approval)
Order matters: the server first, the client second. A client that has not seen `features` never sends `due_time`.

| # | Step | Writes hosted state | Exit criterion |
|---|---|---|---|
| 0 | **Read-only preflight (section 4.1)** | no | baseline matches the recorded one; `tasks` has no `due_time` column; row counts recorded |
| 1 | **Dry run in a rolled-back transaction**: `begin; <migration>; <section 4.2 queries>; rollback;`, then 4.1 again | no (rolled back) | no error; catalog after the rollback identical to step 0 |
| 2 | **Apply** the migration (one file, one call, bytes unchanged, digest compared) | yes | section 4.2 all pass; no new advisor finding |
| 3 | **Hosted HTTP/JWT check with a synthetic account** (section 4.4) | yes (test rows only) | all expectations of 4.4 |
| 4 | **Client check**: install the sync-enabled DEVELOPMENT TEST build of version 1.1.0+2, sign in with the existing test account, set a due time, see it on a second device | yes (test rows only) | acceptance rows F10 to F14 of `phase-5-acceptance.md` |

Stop at the first failed criterion (stop procedure: `combined-hosted-acceptance-operation.md` section 5). Do not run the next step.

## 4. Verification queries
### 4.1 Preflight [read-only]
```sql
select version from supabase_migrations.schema_migrations order by version;          -- last: the S9 version (20261113094553)
select count(*) as tasks, count(*) filter (where due_date is not null) as dated from public.tasks;   -- record
select column_name from information_schema.columns where table_schema='public' and table_name='tasks' and column_name='due_time';  -- 0 rows
select count(*) from public.sync_conflicts where status = 'open';                      -- record (open conflicts are not affected)
select relname, relacl::text from pg_class where relnamespace='public'::regnamespace and relname in ('projects','tasks') order by 1;  -- S9 baseline
```
Also record the security and performance advisors.

### 4.2 After applying [read-only]
```sql
select column_name, data_type, is_nullable from information_schema.columns
 where table_schema='public' and table_name='tasks' and column_name='due_time';       -- due_time | time without time zone | YES
select conname, pg_get_constraintdef(oid) from pg_constraint where conname = 'tasks_due_time_needs_date';
select count(*) as tasks, count(*) filter (where due_time is not null) as with_time from public.tasks;   -- same task count as 4.1; with_time = 0
select p.oid::regprocedure::text, p.prosecdef, p.proconfig, p.proacl::text from pg_proc p
 where pronamespace = 'nexora_private'::regnamespace
   and proname in ('guard_row','patch_spec','apply_core','resolve_core','register_device','pair_due_time') order by 1;
 -- DEFINER (except patch_spec, pair_due_time: invoker, immutable), search_path='' where set before, NO EXECUTE for anon/authenticated on the private functions
select has_function_privilege('authenticated','public.nexora_register_device(uuid, text)','execute') as register_ok,
       has_function_privilege('anon','public.nexora_register_device(uuid, text)','execute') as anon_register;   -- true / false
select relname, relacl::text from pg_class where relnamespace='public'::regnamespace and relname in ('projects','tasks') order by 1;  -- identical to 4.1 (S9 intact)
select nexora_private.patch_spec('task', false) ? 'due_time';                           -- true
select tgname, tgenabled from pg_trigger where tgrelid = 'public.tasks'::regclass and not tgisinternal order by 1;  -- unchanged set, still enabled (ALWAYS)
```
Then compare the security and performance advisors with the preflight record.

### 4.4 Hosted HTTP/JWT check (writes test rows)
Publishable (anon) key plus the synthetic account's access token only; never the service-role key. Over HTTPS: (a) register a device: the answer contains `features: ["due_time"]`; (b) push a create with `due_date` and `due_time: "17:30"`: `applied`, the row shows `due_time: "17:30:00"`; (c) push `due_time: "09:00:30"`, `"24:00"` and a time on an undated task: each `rejected: invalid_patch`; (d) push an update with only `due_date` on a timed task: `applied`, `due_time` null (the older-client rule); (e) pull returns `due_time` in the row; (f) direct `PATCH` on `tasks` is refused (S9). Delete the synthetic account's rows only on the owner's instruction.

## 5. Rollback and recovery
| Situation | Action | Data impact |
|---|---|---|
| Step 1 or 2 fails | the migration is one transaction per file: a failure leaves the previous state; re-run 4.1 | none |
| Applied, verification fails, **no time stored yet** | run `supabase/rollback/20261116100000_rollback_due_time.sql` (one transaction), then 4.1 | none (no time exists) |
| Applied and used, a problem is found | **first stop updated clients** (they would get `invalid_patch` after a rollback); back up `select id, owner_id, due_date, due_time from public.tasks where due_time is not null`; run the rollback | **drops every stored time (dates are untouched)**; documented and tested; the backup lets the owner re-apply |
| Updated clients after a rollback | they notice at their next start: registration no longer lists `due_time`, so the time is switched off, new times are refused locally, dates keep syncing. A **pending** operation that still carries a time is rejected `invalid_patch` (terminal, kept as history); the user edits the task again | one task edit may need repeating |
| Kill switch, no schema change | the client-level and grant-level switches of `combined-hosted-acceptance-operation.md` section 6 | none |
Forward fix instead of rollback: a new migration file with a new digest and a new review.

## 6. Client and version policy
| Client | Behaviour against the migrated server | Limitation |
|---|---|---|
| Version 1.1.0+2 and later (this work) | full: set, change, clear, sync, conflicts, import | none known |
| Any earlier synchronization build (Phase 3 and 4 development builds) | works unchanged: never sends or reads `due_time`; title, notes and status edits leave a time alone; **changing or clearing the date clears the time** on the server (and so on every updated client) | a time set on an updated device can be lost when an older device edits that task's date. **Proposed minimum policy:** devices that edit due dates should be updated to 1.1.0+2 before due times are used on that account; older devices should not be used for date edits afterwards. The server cannot refuse them (it cannot know a client's version), and an unversioned refusal would also block date-only work. |
| Local-only builds | no synchronization: unaffected | none |
| A version 5 local file (the running 1.0.0+1 local-only build) | opened by 1.1.0+2 and migrated in place: times kept, moved into the column | the older build refuses a version 6 file untouched: do not go back after upgrading |

## 7. Owner decisions needed
1. Approve or reject **this exact operation** (section 3, steps 0 to 3), with the digests above.
2. Confirm the minimum client policy of section 6 (a documented limitation, not enforced).
3. After step 4: whether to keep time of day enabled for the TEST account.
Nothing else is requested. No secret is needed by this document or by the build (the build embeds only the public URL and anon key already used by `windows-sync-dev-build`).
