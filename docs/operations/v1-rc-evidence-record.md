# V1 release candidate: evidence record

Baseline head before this package: `25a3fb3`. Evidence below is for the code head `bce9d33` (all later commits change documentation only; the exact-final-head runs are listed in the final report of the package, because a record cannot contain the id of a run on the commit that contains it).

| Area | Evidence |
|---|---|
| Windows CI (format, analyze, all Flutter tests, SQLite restart check, release build, ZIP smoke test) | `CI` run 43380066693 on `bce9d33`: success |
| Disposable PostgreSQL 17 suites, concurrency, rollbacks, mutations (52 caught, 0 missed), limit measurements | `supabase-schema-tests` run 43330018159 on `d189127`: success (no SQL changed afterwards) |
| Real PostgREST and GoTrue: JWT paths, S9 direct writes refused over HTTP, RPC path works | `http-integration` run 43330022802 on `d189127`: success |
| Two-device end-to-end synchronization | `e2e-sync` run 43330009414 on `d189127`: success |
| Local import (preview, atomicity, backup, duplicates, hierarchy, notes, failure rollback, never-offered classes) | `test/features/tasks/data/local_import_test.dart`, `test/app/import_ui_test.dart`, S8-01 (empty account, user-initiated project) in the Windows CI run above |
| Hosted read-only preflight | `hosted-readonly-preflight-2026-11-12.md` (no hosted write) |

Not verified by this package: hosted behavior of any new migration, hosted timings, the Auth settings listed as UNVERIFIED, a real Windows DPAPI round trip with a real signed-in session (the DPAPI branch of the S8 tests runs on the Windows runner; the live-account round trip belongs to the hosted acceptance operation).
