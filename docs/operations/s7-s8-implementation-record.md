# S7 and S8 implementation record: authentication, sync wiring, HTTP/JWT environment, acceptance suite (local, flag OFF)

Authorization: owner message "Phase 3 Complete S7 + S8 Auth and Integration Package" (2026-11-12). No hosted Supabase write, no change to hosted Auth
configuration, no activation, no real user database migration. Status, gates and decisions: `docs/coordination/status-register.md`. Server contract:
`docs/architecture/s3-s4-wire-contract.md`. Hosted preparation: `docs/operations/hosted-deployment-checklist-s2-s4.md`.

## 1. What was built
| Area | Files | Behavior |
|---|---|---|
| Session model and claims | `lib/features/auth/auth_session.dart` | tokens held in a value object; `JwtClaims.parse` reads sub, exp, role, `is_anonymous` (no signature check client side; the server verifies every call) |
| Auth service client | `lib/features/auth/auth_api.dart` | Supabase Auth over `dart:io`: password sign-in, refresh, sign-out; only the public key is sent; typed failures (invalid credentials, unconfirmed email, rate limit, revoked session, network) |
| Protected storage | `lib/features/auth/secure_store.dart` | Windows DPAPI (current-user scope) through the PowerShell that ships with Windows: no new dependency; the secret travels on stdin as Base64, never on the command line; atomic file replace; in-memory store for tests |
| Session manager | `lib/features/auth/session_manager.dart` | restore without network; anonymous identities refused; single-flight refresh; rotated refresh token stored before use; a refused refresh clears tokens but keeps the account id (`reauthRequired`); sign-out always clears tokens, even offline |
| Per-account storage | `lib/features/auth/account_paths.dart`, `lib/runtime/sync_runtime.dart` | signed out: the local workspace (`nexora.db`); signed in: `accounts/<user-uuid>/nexora.db`, one file per account; a file is never opened for another account; only a UUID can become a folder name |
| Real transport wiring | `lib/features/sync/authenticated_transport.dart`, `token_source.dart`, `lib/runtime/session_token_source.dart` | the account the database is bound to must equal the signed-in account **before every call**; one refresh and one retry on an unauthenticated answer; anonymous never retried |
| Runtime | `lib/runtime/sync_runtime.dart`, `sync_scheduler.dart`, `runtime_config.dart`, `app_host.dart`, `lib/main.dart` | built only when `NEXORA_SYNC=true` and project settings are present; no engine, scheduler or transport exists while signed out; a service-role key in the settings is refused; plain HTTP only for this machine |
| UI | `lib/app/account_panel.dart`, `sync_panel.dart` | sign-in dialog, account bar, sync status and "Sync now"; absent in the default build |
| Workspace refresh | `TaskWorkspace.refresh` | after a cycle the workspace re-reads storage, but never while a draft is open (a stale draft must not overwrite pulled data) |

The default build is unchanged: `NEXORA_SYNC` is `bool.fromEnvironment`, default false, `main.dart` runs the original start path, and the adapter is never constructed.

## 2. Data-preservation and isolation rules (all tested)
* Local data is never silently attached to an account. The signed-out local workspace and each account database are different files; unclassified and local-only rows (v1 history, demo data) stay in the local file and never reach the server.
* Account switching: signing out of A and into B opens B's own file; A's file is untouched and unreachable from B; signing back in as A shows A's data.
* An expired or revoked session keeps the account database usable offline (`reauthRequired`); pending operations stay queued and are sent after the next sign-in.
* A corrupt or unreadable session record becomes "signed out" and is removed (it holds only tokens).
* A refresh that returns a different account, or an anonymous one, is refused and never adopted.
* Background errors never escape the scheduler; a manual cycle surfaces them.

## 3. The HTTP/JWT environment (real boundary)
Workflow `.github/workflows/http-integration.yml`: the Supabase CLI (`supabase/setup-cli` pinned by commit, CLI 2.122.1) starts a disposable local stack on the runner (Kong gateway, GoTrue Auth, PostgREST, PostgreSQL 17); the real S1-S4 migrations are loaded; the Dart suite `test/http/` then runs the **production** `SupabaseAuthApi`, `SupabaseSyncTransport`, `SessionManager` and `SyncEngine` against it. There are no secrets; the stack's demo keys exist only in the job. The service-role key is used only by the test harness to read rows past RLS and to delete a test user; no application code receives it.

What it proves through the real API: token issuance and the claims; PostgREST verifying a correctly signed expired token (server calls it expired), a future-dated forged signature (refresh once, retry once), and a deleted user with a still-valid token (refused, cannot refresh); anonymous identities rejected by the client and the server; the public key alone cannot call any sync RPC; `nexora_private` is not exposed (`PGRST106`) and the OpenAPI document lists only the five sync RPCs for a user; another user reads nothing of an account's rows and cannot change or plant rows; every contract error code arrives with its stable code (`device_invalid`, `invalid_cursor`, `invalid_request`, `batch_too_large`); a foreign user cannot use another account's device; a revoked device is refused and its engine pauses without data loss; a response lost after the server commit is replayed idempotently (one operation, version 1); complete two-device synchronization with edits, a conflict resolved through HTTP and an atomic tree delete; an invalid cursor is recovered without data loss; a tree manifest over the size limit is refused and nothing is deleted; refresh rotation (a new refresh token every time).

## 4. Findings (recorded, none changed by this package)
1. **Direct table writes are still granted** (blocker B-10): through the Data API an authenticated owner can INSERT a project directly (HTTP 201 in the S9 probe). RLS blocks writing as another user and reading other users' rows, but direct writes bypass the sync protocol (no `change_seq` stream guarantees beyond the triggers, no operation history). S9 (removal of the grants) stays open: plan in `docs/operations/s9-direct-grants-removal-plan.md`.
2. **Access tokens are stateless.** Signing out or revoking a session ends the refresh token, but an access token already issued keeps working until it expires (default one hour). A deleted user is refused by the sync RPCs immediately (the RPC checks `auth.users`), but table reads through RLS by a deleted user's token are not part of any sync path. Recommendation: keep the JWT expiry at one hour or less (owner decision, Auth dashboard audit).
3. **The refresh-token reuse window is longer than the configuration suggests.** In the disposable stack a refresh token that was already rotated was still accepted twelve seconds later (the first draft of the HTTP suite asserted the opposite and was corrected). The hosted project's reuse interval must be read and decided in the Auth audit (`docs/operations/auth-dashboard-audit.md`); the client always uses the newest refresh token.
4. **DPAPI through PowerShell** adds a process start (a few hundred milliseconds) per session read or write; it protects against other Windows users and against file copies to another machine, not against code running as the same user. A native or package-based store would need dependency approval.
5. **A fresh account gets one default project after its first complete cycle if the server holds none.** Two devices that sign in at the same moment on an empty account can each create one; they are then two ordinary projects (no data loss). Recorded as an owner product decision (O-17).

## 5. Evidence
Recorded in the status register evidence index (run ids of the exact final head). Local limits: no Dart SDK exists in the agent environment, so formatting, analysis and the Windows tests run only in CI.

## 6. Not verified, still open
* The hosted project: nothing was applied or changed there. Hosted HTTP/JWT acceptance is prepared but not run (B-20 stays open until an owner-approved hosted run).
* Real Windows Credential/DPAPI behavior on a user's machine beyond the CI runner.
* Email confirmation, password reset and sign-up flows (the application only signs in; account creation and recovery are outside this package).
* Behavior of the hosted Auth settings (D-U audit not performed).
