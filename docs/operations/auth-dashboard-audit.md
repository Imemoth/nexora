# Auth configuration audit (D-U) — partly read, partly UNVERIFIED

**Status update (2026-11-14): decision D-U is settled for the TEST environment (public sign-up stays enabled during development; anonymous users are rejected by client and protocol; see the register). Remaining items below are a production Auth review, which is out of scope for now.**

Status: **partly verified** (2026-11-12, read-only, see the table below and `hosted-readonly-preflight-2026-11-12.md`); everything not listed as observed is **UNVERIFIED** and must not be assumed compliant. The original statement follows.

Original status: **unverified.** The session cannot read the Supabase Dashboard auth settings. This must be completed by the owner (or with explicit access) **before authentication or synchronization activation**.

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

## Configuration audit checklist for S7 (prepared, NOT yet audited)
Status: **nothing below has been verified.** No hosted Auth setting was read or changed while preparing this checklist; the "Observed" column stays empty until the owner (or a read-only Management API call the owner approves) records it. The desktop app (S7) signs in with email and password against Supabase Auth, keeps the refresh token in Windows protected storage, refreshes access tokens itself and never holds a service-role key. The server rejects anonymous identities and deleted users regardless of these settings (`nexora_private.sync_user()`; tests in `supabase/tests/s2_auth_grants_test.sql`), so the settings below are the first line of defence and the source of the user experience, not the only protection.

| # | Setting (Dashboard path under Authentication) | Expected value or recommendation | How to verify (read-only) | Observed |
|---|---|---|---|---|
| 1 | Email provider enabled (Sign In / Providers) | On: this is the only sign-in method the app uses | Dashboard, Providers; or Management API `GET /v1/projects/{ref}/config/auth` (read-only) | _record_ |
| 2 | Other providers (phone, OAuth, magic link only) | Off unless the owner wants them; the app has no UI for them | Providers page | _record_ |
| 3 | Allow new users to sign up | Owner decision. Off if accounts are created by the owner in the dashboard; On only with email confirmation (row 5) and rate limits (row 10) | Sign In / Providers, "Allow new users to sign up" | _record_ |
| 4 | Anonymous sign-ins | **Off.** If the owner leaves them on, anonymous users still hold the `authenticated` role; the RPCs refuse them with `anonymous_not_allowed` (42501), and the desktop app treats such a token as unusable, but direct table writes of an anonymous user remain possible until S9 | Providers page, "Allow anonymous sign-ins" | _record_ |
| 5 | Confirm email | On. The app shows a "confirm your email" state for sign-in before confirmation | Providers, Email | _record_ |
| 6 | JWT expiry (Settings, JWT) | Short: 3600 seconds or less; the app refreshes about 60 seconds before expiry and handles an expired token by refreshing once and retrying | Auth settings; the `exp` claim of a test token minus `iat` | _record_ |
| 7 | Refresh-token rotation and reuse interval | Rotation on; reuse interval short (the default of 10 seconds is acceptable). The app stores the newest refresh token before using the new access token and refreshes with a single in-flight request | Auth settings (Sessions / Security) | _record_ |
| 8 | Session time-box and inactivity timeout | Owner decision. Longer sessions suit a desktop app; if a time-box is set, the app must show "sign in again" with local data kept (implemented as the auth-required state) | Auth settings, Sessions (plan dependent) | _record_ |
| 9 | Single session per user | Off (the app supports up to ten devices per user, D-D); turning it on would sign other devices out | Auth settings, Sessions | _record_ |
| 10 | Rate limits (Authentication, Rate Limits) | Defaults or stricter for sign-in, token refresh and sign-up; record the values. These limit password guessing and refresh storms; the app backs off on HTTP 429 | Rate Limits page | _record_ |
| 11 | Password requirements | Minimum length 12 or more recommended; character-class rules at the owner's discretion | Sign In / Providers, Email, password settings | _record_ |
| 12 | Leaked-password protection | On (needs a plan that offers it; if unavailable record that fact) | Same page; also reported by the Security Advisor | _record_ |
| 13 | Multi-factor authentication | Owner decision; the desktop app has no MFA enrolment UI in S7, so enforcing MFA would lock users out. Leave off (or optional) until a later slice | MFA page | _record_ |
| 14 | Site URL and redirect allow-list | Irrelevant to the desktop password flow, but keep only intended URLs (the app uses no redirect); remove wildcard entries | URL Configuration | _record_ |
| 15 | Custom SMTP / email templates | Needed for confirmation and password-reset mail at scale; default sender is rate limited | Auth, Emails | _record_ |
| 16 | Manual account linking, user deletion behaviour | Record. A deleted user's still-valid access token is refused by the RPCs; refresh then fails and the app shows the signed-out state with local data kept | Auth settings | _record_ |
| 17 | Auth hooks and attack protection (CAPTCHA) | Record whether any hook alters claims; claims such as `sub`, `role`, `is_anonymous` must not be changed by hooks (the server trusts `auth.uid()` and the `auth.users` row, never user-editable metadata) | Auth, Hooks and Attack Protection | _record_ |

How to record results: add the observed value and the date to this table in a later change, and update decision D-U in `docs/coordination/status-register.md`. A read-only Management API call needs a personal access token that the owner provides for that one call; the token must not be stored in the repository or in logs. Until every row is recorded, authentication activation stays NO-GO.

## Read-only observations of 2026-11-12 (public settings document and read-only SQL; nothing changed)
| Requirement (release candidate) | Observed | Verdict |
|---|---|---|
| Anonymous sign-ins disabled | disabled | meets |
| Public sign-up disabled (initial personal-use release) | **enabled** | **does not meet**; owner action in the dashboard (B-AUTH-1) |
| Email provider and confirmation | email on, confirmation required | meets |
| JWT expiry at most 3600 s | not readable | UNVERIFIED |
| Refresh-token rotation and reuse window | not readable | UNVERIFIED |
| Multiple concurrent device sessions (single-session-per-user off) | not readable | UNVERIFIED |
| Password policy, leaked-password protection | not readable | UNVERIFIED |
| Rate limits (sign-in, refresh, sign-up) | not readable | UNVERIFIED |
| MFA compatibility and recovery | not readable; the desktop app has no MFA enrolment UI, so MFA must stay off or optional | UNVERIFIED |
| Data API exposed schemas | `public`, `graphql_public`; `nexora_private` absent | meets |

Owner decisions needed before the combined operation's HTTP step (see `remaining-blocker-register.md`): turn public sign-up off and create the accounts in the dashboard; read and record the UNVERIFIED rows (or approve a read-only Management API check); confirm JWT expiry at or below 3600 s. No dashboard setting was changed by this document.

## Hosted observations of 2026-11-13 (public settings document, a real sign-in, the advisor; nothing changed)
| Item | Observed | Note |
|---|---|---|
| Public sign-up | enabled (`disable_signup: false`) | allowed during development by owner decision of 2026-11-13; not a blocker |
| Anonymous sign-ins | disabled | meets |
| Email provider, confirmation | email on, `mailer_autoconfirm: false` | confirmation required |
| Other providers (phone, OAuth, SAML, passkeys) | all off | meets |
| JWT expiry | `expires_in` 3600 s on a real sign-in | meets the 3600 s limit |
| Refresh token | returned with every password sign-in | rotation and reuse window UNVERIFIED |
| Concurrent sessions | two accounts signed in together; per-user session limit UNVERIFIED | |
| MFA, password policy, Auth rate limits | not readable | UNVERIFIED |
| Leaked-password protection | **disabled** (security advisor WARN) | enable before real users; not needed for the test environment |
| Exposed Data API schemas | `nexora_private` request answered `406 Invalid schema: nexora_private` | not exposed; `public` is |
