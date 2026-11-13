# V1 release acceptance checklist

Tick each line with evidence (run id, file, or note). A line without evidence is not accepted. Exact-head CI means the workflow runs listed for the final commit; the final report records the ids.

## A. Build and packaging (Windows)
- [ ] `CI` workflow green on the exact final commit: format, analyze, all Flutter tests, SQLite restart check, Windows release build, portable ZIP smoke test.
- [ ] `SHA256SUMS.txt` produced and attached to the run; ZIP hash recorded in the report.
- [ ] Flutter 3.47.9 and Dart 3.13.7 verified by the workflow; `flutter pub get --enforce-lockfile` passed.

## B. Local data safety
- [ ] SQLite v1 to v2 migration on synthetic and disposable copies, backup verified, v1 sent/failed states not replayed (tests: `test/features/tasks/data/migration_*`, `test/s8` S8-02).
- [ ] Local import: preview writes nothing; atomic write; new ids and mapping stored; hierarchy, notes, status, priority, due dates kept; source unchanged by digest; verified backup holds the pre-import state; failure injection rolls everything back; duplicates detected; local-only and unclassified never offered; pending outbox untouched (`test/features/tasks/data/local_import_test.dart`).
- [ ] Import UI: empty-account notice, preview, per-project destination, warnings, failure message (`test/app/import_ui_test.dart`).
- [ ] No automatic default project in account workspaces (S8-01).

## C. Authentication and isolation
- [ ] Windows DPAPI round trip on a real Windows runner (S8 tests, `Platform.isWindows` branch) and the session file is not plain text.
- [ ] Token refresh, revoked device, logout, account switch; two accounts on one machine never share a database; two devices of one account converge (S8, e2e).
- [ ] Anonymous token refused by server and client.

## D. Synchronization
- [ ] Offline then online sync; lost-response replay is idempotent; conflict detection and resolution; tree delete; pull cursor (e2e-sync workflow, S8).
- [ ] `NX007 rate_limited` is retried with backoff and never marks operations failed; `payload_too_large` halves the batch.
- [ ] `NEXORA_SYNC` is off in the default build and in the RC ZIP.

## E. Server (disposable PostgreSQL 17)
- [ ] `supabase-schema-tests` workflow green: all suites, S9 ordering (legacy direct-write suites before S9), concurrency scripts, rollback verification, 52 mutations caught, 0 missed, limit measurements within ceilings.
- [ ] `http-integration` workflow green: real PostgREST and GoTrue, JWT paths, S9 direct writes refused over HTTP, RPC path works.
- [ ] Bounded responses, request-size and execution-time limits, per-user throttle measured (`hardening-implementation-record.md`).

## F. Documentation
- [ ] `docs-check` workflow green (index, migration table, policy rules).
- [ ] Install, first-run, sign-in, backup and recovery guide, deployment operation, kill switch and blocker register present and linked from `docs/README.md`.

## G. Hosted (not part of RC acceptance; recorded for the next gate)
- [ ] Hosted read-only preflight recorded (`hosted-readonly-preflight-2026-11-12.md`).
- [ ] Owner authorization of the combined operation (not yet given).
