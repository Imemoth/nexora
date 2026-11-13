# Windows first sign-in hang: investigation and fix (2026-11-13)

Report: in the sync-enabled DEVELOPMENT TEST build (run 43406456870) the first sign-in stays in the "Sign in to synchronize" dialog, the button stays disabled, no error is shown, and the Auth service logged HTTP 200 for `POST /token` with no later request.

## 1. What was proven, and what was not
**Traced path:** dialog `_submit` -> `SyncRuntime.signIn` -> `SessionManager.signIn` -> `SupabaseAuthApi` -> protected store (`DpapiSecureStore`) -> `_activate` (open the account database, build the engine) -> workspace swap in `AppHost`.
**Evidence gathered on a real Windows runner, inside the packaged `nexora.exe` (`NEXORA_AUTH_SELFTEST`, no UI, no network, real runtime):**
| Step | Result |
|---|---|
| PowerShell DPAPI protect (first call) | 1,889 ms and 3,022 ms in two runs; unprotect 258 to 292 ms; exit 0 |
| Native in-process DPAPI round trip | 12 to 14 ms |
| Native reads a value written by PowerShell | works (same file format) |
| Sign-in -> persist -> account database -> state; restart restores the session; sign-out; sign-in again | all complete; each under 300 ms after the first PowerShell call |
So on that runner **the PowerShell DPAPI call and the whole lifecycle do not hang.** That run still had a console attached (`stdinTerminal=true`). A probe without any console (started through WMI) never reached the program's first line (it runs in a non-interactive session where the Flutter engine does not start), so it says nothing about DPAPI and was removed.
**Honest conclusion:** the hang was **not reproduced** in CI, so the exact blocking call on the owner's computer is not proven by this work. What is proven is a set of defects that each produce precisely the observed symptom (a dialog that never ends, disabled button, no message) whenever *any* step of the sign-in does not complete or throws, and the most likely trigger on a desktop computer is the helper-process DPAPI call (a console program started from a GUI program, 2 to 3 s even when healthy, with no time limit).

## 2. Defects found and fixed
| # | Defect | Effect | Fix |
|---|---|---|---|
| 1 | The sign-in dialog had no `try`/`finally` and no timeout | any exception, or any step that never completes, left the button disabled forever with no message | contained errors, 120 s limit, error text, retry (`account_panel.dart`) |
| 2 | The PowerShell helper had no time limit and its start/stdin errors were not contained | a stuck or failing helper blocked sign-in indefinitely | bounded (30 s per call, 45 s per store operation), process killed on timeout, every failure becomes `AuthStorageFailure` (`secure_store.dart`) |
| 3 | Sign-in required the session to be saved before it succeeded | a store problem blocked the whole sign-in | the session is kept in memory when saving fails and the UI shows the existing storage notice (`session_manager.dart`) |
| 4 | `SessionManager.restore` and `_safeDelete` caught only auth-specific errors | an unexpected store error at start could stop the application | any store failure is contained |
| 5 | `_doActivate` closed the current workspace before opening the account's | a failed open (disk, permissions) left a closed workspace active | the new workspace is opened first; on failure the sign-in is undone, local data untouched, outcome `accountStorageFailed` (`sync_runtime.dart`) |
| 6 | The activation chain was a plain `then` chain | one failed activation permanently disabled every later one (no retry without restart) | failures are reported to their caller and never poison the chain |
| 7 | Auth/runtime exceptions other than `AuthFailure` propagated | unhandled exception, stuck dialog | mapped to `SignInOutcome.failed` with a log line |

## 3. The main change: no helper process for DPAPI
DPAPI (current-user scope) is now called in-process through `Crypt32.dll` (`native_dpapi.dart`, `dart:ffi`, no new package): about 12 ms instead of 2 to 3 s, no console program, no standard-input wait. It uses the same entropy and file format, so existing `session.dpapi` files stay readable and either implementation reads the other's files (verified in CI and in the packaged exe). `windows_secure_store.dart` selects it, falls back to PowerShell if the native library cannot be set up, and honors `NEXORA_DPAPI=powershell` for diagnostics.

## 4. Diagnostics (development builds)
`%LOCALAPPDATA%\Nexora\diagnostics\signin.log` (cut at about 256 KiB) records step names and durations of the sign-in lifecycle: `signin.api.start/ok`, `signin.persist.start/ok/failed`, `dpapi.*`, `runtime.activate.*`, `runtime.signin.ok`. It never receives passwords or tokens (secret-looking keys are dropped; tested). **If sign-in still stalls, the last line of this file names the step; send it.**
The packaged executable also has a no-UI self-test (`NEXORA_AUTH_SELFTEST=<file>`), run by the DEVELOPMENT TEST workflow before packaging.

## 5. Regression tests (all in Windows CI; the Windows-only ones are skipped elsewhere)
* `test/features/auth/signin_lifecycle_test.dart`: first sign-in (account database, session saved), restart restores it, storage failure and unexpected store exception do not strand the sign-in, auth-layer exception releases the dialog, **account database failure keeps local data and a retry works**, network failure then retry, sign-out then sign-in again keeps the account data, the log never holds the password or a token.
* `test/features/auth/secure_store_test.dart`: timeout (`dpapi_timeout`), contained protector exceptions, unstartable program, **a stuck helper is killed (Windows)**, **real native DPAPI: round trip, restart, cross-compatibility with PowerShell, damaged blob (Windows)**.
* `test/app/sign_in_dialog_test.dart`: success closes the dialog; failure shows the error and re-enables the button; an unexpected exception is contained and a retry works; an operation that never completes ends with a timeout error; account-folder failure has its own message.
* `test/runtime/app_host_signin_test.dart`: sign-in through the real UI and runtime (dialog closes, account workspace shows, empty-account notice), failed sign-in then retry, sign-out and sign-in again, import panel only when signed in.
* S8 acceptance tests (real DPAPI on Windows) still pass.

## 6. What the owner should do
Run the new DEVELOPMENT TEST artifact and sign in. Expected: the dialog closes within a second or two and the account workspace (empty, with New project and Import local data) appears. If it does not, send `%LOCALAPPDATA%\Nexora\diagnostics\signin.log`.
