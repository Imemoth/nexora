# Phase 3 integration review (development branch to `main`)

Date: 2026-11-14. Branch `claude/affectionate-turing-unzmd2` against `main` (`46227c8`): 194 files (168 added, 26 modified). Status of everything below: `docs/coordination/status-register.md`.

## 1. Hosted and repository consistency (read-only check)
Hosted migration history of the TEST project (read through the read-only migration list on 2026-11-14): 12 entries = the initial schema (applied through the connector, not stored in the repository) plus the 11 files in `supabase/migrations/`, in the same order, with the stamped versions in register section 2. No entry exists on the hosted side that has no repository file, and no repository file is missing on the hosted side. Function bodies were verified identical to the repository files at apply time (acceptance record). **No additional migration is part of this integration.**

## 2. Integration risks found in the diff
| # | Finding | Risk | Handling |
|---|---|---|---|
| 1 | `.github/workflows/windows-sync-dev-build.yml` has a `push` trigger bound to the branch name `claude/affectionate-turing-unzmd2` (path-filtered to the workflow file) | harmless on `main`, dead trigger after the branch is deleted | keep for the merge; owner may remove the `push:` block afterwards; `workflow_dispatch` is what is used |
| 2 | The same workflow embeds the TEST project URL and the **anon (publishable) key** | the key is public by design (role `anon`) and RLS plus S9 protect data; no service-role key or password is anywhere in the repository (scanned) | accepted for the TEST environment; move to repository variables before any non-test use |
| 3 | The default build keeps `NEXORA_SYNC` off; only the dev-build workflow turns it on | merging does not activate sync for the default portable ZIP | verified by the default `CI` build (no network code path without the flag) |
| 4 | `SyncStatus.openConflicts` semantics changed (now counts actionable conflicts) | consumers outside the sync UI | all in-repo consumers updated; covered by tests |
| 5 | `.gitignore` ignores `test/golden/failures/` | hides local golden failure images only | accepted |
| 6 | `tool/hosted_acceptance.py` talks to the hosted project | needs credentials | reads them only from environment variables, never stores them; not run by CI |
| 7 | `supabase/rollback/` scripts are never run by the test runner or CI against the hosted project | none | documented in the runbook |
| 8 | Seven workflows now run on pull requests; Windows CI is the long one | CI cost | accepted |
| 9 | No Dart dependency added (`pubspec.yaml` unchanged); native DPAPI uses `dart:ffi` | none | confirmed by diff |
| 10 | Linux-only local failures (golden images, one path-separator test, three S8 tests) are not CI failures | none on the Windows CI target | all green on Windows CI |

## 3. Out of scope and unchanged
No production hardening, no deletion of test data or accounts (test@test.com, nx-accept-a/b@example.test, about 1,022 test tasks stay), no hosted Auth change, no force-push or rebase.
