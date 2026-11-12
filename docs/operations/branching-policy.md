# Git branching policy

Status: adopted by the owner on 2026-11-12.

## Rules
1. `main` is the stable integration branch. It changes only through an owner-approved merge commit.
2. Keep **one active development branch per coherent development stream** (for example: app UI, local persistence, Supabase and sync, documentation).
3. Continue related work on the stream's existing branch whenever practical. Do not create a branch per implementation slice or per task.
4. Create a separate branch only for a change that is genuinely independent, risky, or conflicting with the stream's current work.
5. Do not rebase or force-push shared branches. Bring `main` in with a merge commit.
6. Do not delete branches without owner approval. A merged branch may be reused for the next increment of its stream.
7. Open a pull request only when the owner needs to review or approve a merge. Do not open one per commit or per slice.

## Gates that do not change
- No hosted database migration, secret change, deployment, release, or synchronization activation without separate owner approval.
- Documentation-only changes must be reviewable as documentation only: a branch that also carries unapproved implementation is not used for a documentation pull request.

## Proposed streams
| Stream | Branch | Holds |
|---|---|---|
| Integration | `main` | Approved, merged work only |
| Documentation | `docs/phase-0-implementation-plan` (reused after PR #1; rename only with owner approval) | Specs, plans, ADRs, shared contracts, operations records |
| Local persistence (Phase 2A) | `feature/phase-2a-sqlite` | SQLite repository, migrations, outbox |
| Supabase and sync (Phase 2B/3) | `claude/affectionate-turing-unzmd2` | Supabase migrations, SQL tests, sync server work, S1 until approved |
| Client sync (Phase 3, later) | continue on the Phase 2A stream branch unless it conflicts | Dart sync engine |

Existing finished or superseded branches (`feature/phase-1-*`, `docs/phase-1-desktop-ui-plan`, `feature/phase-0-foundation`) stay until the owner approves cleanup.
