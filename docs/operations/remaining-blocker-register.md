# Remaining blocker register (V1 release candidate)

> **Update 2026-11-13.** The owner authorized the combined operation for the hosted TEST project and it was executed (`hosted-acceptance-record-2026-11-13.md`). B-AUTHZ, B-AUTH-1, B-ACCT and B-PG17H are resolved or withdrawn (public sign-up stays on during development by owner decision; the synthetic acceptance accounts exist). Still open: B-AUTH-2 (some Auth settings remain UNVERIFIED, not blocking development), B-ACT (activation for real users, out of scope: test environment), B-SIGN, B-RET.


Only items that block the stated next step are listed. "Next step" is the combined hosted acceptance operation (`combined-hosted-acceptance-operation.md`) unless stated.

| ID | Blocker | Blocks | Owner action | Status |
|---|---|---|---|---|
| B-AUTHZ | Written authorization of one combined hosted operation (hosted migrations S2 to S4, throttle, response bound, S9, synthetic account) | the operation | Authorize, after reading the runbook | open |
| B-AUTH-1 | Public sign-up is **enabled** on the hosted project; the initial release requires it off | HTTP acceptance step and activation | Turn off "Allow new users to sign up" in the dashboard; create accounts there | open (observed 2026-11-12) |
| B-AUTH-2 | JWT expiry, refresh-token rotation and reuse window, concurrent sessions, password and rate-limit policy, MFA setting are **UNVERIFIED** | activation | Read them in the dashboard (or approve a read-only Management API check) and record in `auth-dashboard-audit.md`; JWT expiry must be at most 3600 s | open |
| B-ACCT | A dedicated synthetic test account (throw-away password) and later the owner's real account must be created in the dashboard | HTTP acceptance step | Create and confirm the accounts | open |
| B-ACT | Build with `NEXORA_SYNC=true` and project settings, and activation of synchronization for real use | activation | Separate authorization after a successful operation | not started, by design |
| B-SIGN | The ZIP is unsigned (SmartScreen warning) | wider distribution, not a personal pilot | Accept for the pilot or provide a code-signing certificate | accepted for pilot unless the owner objects |
| B-RET | Operation-log retention is a design only (`rate-limit-and-log-retention-recommendations.md`, section 3a); nothing prunes history | very long use, not V1 pilot | Decide a retention window before the log grows large | design only |
| B-PG17H | Hosted timing and response sizes unmeasured (local numbers only) | S9 and activation | Measured in step 6 of the operation | pending the operation |

Not blockers (resolved or accepted): the Windows DPAPI storage is retained (no material defect found); the throttle defaults are generous and data-driven; direct table-write removal (S9) is implemented and tested but applied only inside the operation.
