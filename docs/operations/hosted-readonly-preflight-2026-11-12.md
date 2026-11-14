# Hosted read-only preflight, 2026-11-12

**Note (2026-11-14): this record describes the state at the time it was written. Statements such as "not applied to hosted", "disabled" or "not run" are historical; the hosted TEST deployment and Phase 3 acceptance are recorded in `docs/operations/hosted-acceptance-record-2026-11-13.md` and the current status is in `docs/coordination/status-register.md`.**

Scope: read-only checks of the hosted project (`uicccaawtjvqggeufbez`, PostgreSQL 17.11) made while preparing the release candidate. **No hosted write, no Auth configuration change, no service-role key** was used. Queries were `select` statements through the read-only query tool; the public Auth settings document was read with the publishable key only. No key value is recorded here.

## Results
| Check | Result |
|---|---|
| Migration history | exactly six migrations: `20261112111349`, `20261112115809`, `20261112120132`, `20261112120149`, `20261112142732` (F1), `20261112151851` (S1). S2, S3, S4 and every later file are **not applied**. |
| Data | `auth.users` 0 rows, `projects` 0, `tasks` 0. Nothing to migrate and no real user data on the hosted project. |
| Role settings | `authenticated` has `statement_timeout=8s` (this bounds every sync call; limits are measured in `hardening-implementation-record.md`). |
| Table ACLs | `authenticated` holds `arw` (SELECT, INSERT, UPDATE) on `projects`, `tasks` and `profiles`; `postgres` and `service_role` hold the full set. This is the baseline that S9 removes (writes) while keeping SELECT. |
| Security advisor | no findings (empty list). |
| Data API exposed schemas | `public` and `graphql_public`; `nexora_private` is not exposed. |
| Auth: anonymous sign-ins | **disabled** (read from the public settings document). |
| Auth: email provider / confirmation | enabled, confirmation required. |
| Auth: public sign-up | **enabled**. This does not meet the requirement for the initial personal-use release (sign-up off); changing it is a dashboard action by the owner (blocker B-AUTH-1). |
| Auth: JWT expiry, refresh-token rotation and reuse interval, concurrent sessions, password policy and leaked-password protection, rate limits, MFA, redirect allow-list | **UNVERIFIED**: not readable without a Management API token or the dashboard. Not assumed compliant. |
| OpenAPI root of the REST endpoint | UNVERIFIED: it requires a secret key (HTTP 401 with the publishable key); no service-role key was used. |
| `pg_graphql` | not queried in this pass; recorded absent in the security record. |

## What this means for the operation
The hosted project is in the state the combined operation assumes (`docs/operations/combined-hosted-acceptance-operation.md`, section 4.1 baseline). Before step 5 the owner must decide the UNVERIFIED Auth settings and turn public sign-up off (or accept it explicitly), because the synthetic acceptance account and later the owner's own account are created in the dashboard.
