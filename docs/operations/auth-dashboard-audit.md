# Auth configuration audit (D-U) — NOT YET PERFORMED

Status: **unverified.** The session cannot read the Supabase Dashboard auth settings. This must be completed by the owner (or with explicit access) **before authentication or synchronization activation**.

Project `uicccaawtjvqggeufbez`, Dashboard -> Authentication.

| Setting | Required for V1 | Observed |
|---|---|---|
| Allow new users to sign up | Off unless the owner explicitly wants self sign-up | _record_ |
| Anonymous sign-ins | **Off** | _record_ |
| Email provider and confirm email | Confirmation on | _record_ |
| Other providers | Only intended ones | _record_ |
| Site URL and redirect allow-list | Only intended URLs | _record_ |
| JWT expiry | Short (<= 1 h) | _record_ |
| Leaked-password protection | On | _record_ |

Why it matters: an anonymous user holds the `authenticated` role and a real `auth.uid()`. Today that user can already insert and read its own projects and tasks directly. The Phase 3 RPCs will additionally reject `is_anonymous` JWTs, but the setting should be off.

Evidence so far: `auth.users` has 0 rows (read-only). Nothing else is known.
