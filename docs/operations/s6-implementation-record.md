# S6 implementation record: local synchronization engine (disabled by default)

Contract: `docs/architecture/s3-s4-wire-contract.md` (server) and `docs/coordination/phase-3-s5-outbox-v2.md` (storage). Status and gates:
`docs/coordination/status-register.md`. The feature flag `NEXORA_SYNC` is `bool.fromEnvironment`, default **false**; nothing in the app
creates a transport, so the shipped application makes no network call. No hosted authentication or Supabase project is needed to test the engine.

## 1. Components (`lib/features/sync/`, `lib/features/tasks/data/`)
| Component | Role |
|---|---|
| `sync_transport.dart` | `SyncTransport` interface (register, push, pull, resolve, revoke) and the sealed failure types: network failure, auth failure (anonymous or not), server error with a code |
| `sync_engine.dart` | `SyncEngine.syncNow`: bind account, recover in-flight work, register device, push ordered batches, pull pages, resubmit operations that were blocked by a closed conflict, mark synced. Also `resolveConflict` and `revokeDevice` |
| `backoff.dart` | exponential backoff (2 s start, factor 2, 5 min cap, 20 % jitter) with injected sleep |
| `supabase_sync_transport.dart` | real HTTP adapter over `dart:io` `HttpClient` (no new dependency), PostgREST error mapping; **not wired into the app** |
| `sync_status.dart` | phases: disabled, idle, syncing, retrying, authRequired, deviceRevoked, error; counts of pending, rejected and open conflicts |
| `pull_applier.dart`, `sync_state_store.dart` | one SQLite transaction per pulled page together with the cursor; account binding; staging of rows whose parent has not arrived (`sync_pull_stage`, schema v3) |
| `outbox_store.dart`, `sqlite_task_repository.dart` | tree-delete operation with a claim-time manifest, resubmission of blocked operations, local tree delete for tasks and projects (at most 1000 descendants), server resolutions applied to local rows |
| `test/support/fake_sync_server.dart` | in-memory server with the S2/S3/S4 semantics and deterministic fault injection (lost response after commit, network failure, auth failure, batch size faults) |

## 2. Rules implemented (data preservation)
* Local pending edits are never overwritten by a pull: fields touched by a pending, in-flight, rejected or conflicted operation keep the local value; the server value is recorded in a snapshot and the conflict mirror.
* A tombstone from the server is not applied while local work on that entity is pending; the user decides (conflict).
* Local-only and unclassified rows are never read by the outbox claim or the pull applier; a pulled id that collides with a local-only id raises a protocol error instead of overwriting.
* A server rejection is kept as history and shown as "needs attention"; recovery always uses a new `operation_id` (OD-5). Nothing is discarded automatically.
* Authentication failure, anonymous identity, revoked device and network loss all leave every pending operation intact; status tells the user what to do.
* Replay after a lost response uses the same `operation_id` and `request_hash`, so the server returns the stored result.
* Cursor persistence and page application are one transaction; an `invalid_cursor` resets the cursor to 0 once and rebuilds from the stream without deleting local rows.
* Account binding: the first synchronizing account is recorded; a different account signing in is refused (no data from one account is sent to another).

## 3. Evidence
| Evidence | Result |
|---|---|
| Engine tests with the fake server (`test/features/sync/sync_engine_test.dart`), status bar widget tests (`test/app/sync_status_bar_test.dart`), full suite | Windows CI run 43306627424 on `b90840d`: format, analyze, 447 tests passed, restart check, release build, portable ZIP smoke test, all success |
| Two-device end-to-end suite on PostgreSQL 17 with the real migrations, two real SQLite databases, the real S5 storage and the real engine (`test/e2e/two_device_sync_test.dart`, workflow `e2e-sync`) | 15 scenarios passed (run 43299291266 on `0c1f84e`); scenario list in section 4 |
| Windows CI of the exact final head | recorded in the final acceptance report (documentation commits after `b90840d` do not change code) |

## 4. End-to-end scenarios (all against the real S1-S4 migrations)
1 Device A creates a project and tasks, device B receives them. 2 Independent offline edits of different fields reconcile. 3 Same-field edits: conflict evidence stays on the server and locally; server, local and merged resolutions converge; both original values survive resolution. 3b Edit of a deleted task is recreated as a copy while the tombstone stays. 4 Response lost after the server commit: the retry is idempotent (one operation, version 1). 5 Process crash after the push response: restart recovers the in-flight operation. 6 Tree delete is atomic and orphans nothing; 6b a child added elsewhere turns the delete into a conflict and nothing is deleted. 7 Revoked device cannot continue, keeps its edit. 8 Local-only, demo and legacy (unclassified) rows never reach the server. 9 Authentication failures (deleted user, anonymous, expired token) never delete pending work; the same work goes through after sign-in. 10 A server-side rejection is recorded, the client change is preserved and flagged. 11 Pagination over 230 tasks with a page limit of 100. 12 Unknown cursor is reset. 13 Two devices synchronizing at the same time converge.

## 5. Limitations (stated, not hidden)
* PostgREST and real JWT verification are **not** exercised: the harness calls the RPCs through `psql` as the `authenticated` role with claims set per transaction. The hosted HTTP acceptance gate stays open.
* The Supabase transport adapter is tested only against a local HTTP server, never against Supabase.
* There is no session or sign-in code (S7); the engine takes an injected user id supplier and the app supplies none.
* UI: a status bar and a manual "Sync now" action exist only when a controller is provided and the flag is on; default screens are unchanged.
* Windows restart and release-build verification come from the `CI` workflow of the final head (register evidence index).
