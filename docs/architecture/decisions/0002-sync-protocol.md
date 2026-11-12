# 0002: Synchronization protocol

Status: accepted by the owner on 2026-11-12 (conditions below). Plan: `docs/superpowers/plans/2026-11-12-nexora-phase-3-sync.md`.

## Decisions
| ID | Decision | Status |
|---|---|---|
| D-C | Field-level conflict detection via server-owned `field_versions` | approved |
| D-A | A conflicting operation applies nothing | approved |
| D-P | Parent delete is explicit leaf-first from the client; the server never cascades | approved |
| D-V | Local `version` is server-owned | approved |
| D-T | Tombstones are permanent; no compaction in V1 | approved |
| D-E | Update after delete is a conflict; no undelete | approved |
| D-N | Notes conflict as a whole field | approved |
| D-D | Maximum 10 active devices per user | approved |
| D-X | Disposable PostgreSQL 17 in CI; hosted tests are rollback-only | approved |
| D-F | Build-time feature flag, default OFF | approved |
| D-L | Per-user advisory lock for cursor safety | **conditional**: multi-session tests with a negative control, and every write path must use the same lock (enforced in the guard trigger, `ENABLE ALWAYS`) |
| D-R | Public SECURITY INVOKER wrappers over private SECURITY DEFINER functions | **conditional**: verify exact EXECUTE privileges, `search_path`, ownership checks and non-exposure of `nexora_private` (S2 gate) |
| D-O | Auto server-wins for `sort_order` | **conditional**: losing operation and both values must stay auditable (DB-enforced in S1) |
| D-S | Client dependency architecture | approved in principle; exact versions and Windows secure storage need review before S7 |
| D-U | Anonymous sign-in and public sign-up | **unverified**: audit the dashboard before authentication activation (`docs/operations/auth-dashboard-audit.md`) |

## Consequences
- Direct write privileges are unchanged until the S9 activation gate. Synchronization stays disabled and the flag stays OFF.
- Hosted migrations need separate owner approval; S1 is not applied.

## Implementation status (2026-11-12)
| Decision | Status |
|---|---|
| D-V | Implemented in Phase 2A (PR #13, Draft). Server side applied |
| D-C, D-L, D-O, D-D | Prepared in S1 (PostgreSQL 17 CI green), not applied |
| D-A, D-P, D-T, D-E, D-N | Server enforcement in S2-S3, not built. Tombstone revert block is applied |
| D-R | S2 gate, not built |
| D-S, D-U, D-F | Not started / unaudited. Synchronization is disabled |
See the status table in `docs/architecture/data-contract.md`.
