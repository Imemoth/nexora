# Sync Contract (future phases; not implemented in Phase 0)

> **Update 2026-11-12:** the owner approved the Phase 2B/3 shared contract. Where this Phase 0 document differs, `data-contract.md` and `decisions/0002-sync-protocol.md` apply: ownership is `owner_id` (not `workspace_id`) and the revision is `version` (D1); the envelope's `base_revision` is `base_version`; operation types are `create | update | delete`. The invariants and failure cases below still hold.

This document fixes invariants that Phases 2 and 3 must satisfy. It is a contract, not an implementation.

## Operation envelope
Every local mutation becomes one outbox operation with these fields:
- `operation_id`: UUID, generated on the device, unique per operation
- `workspace_id`: UUID
- `entity_type`: string
- `entity_id`: UUID
- `base_revision`: integer, the revision the edit was based on
- `patch`: JSON
- `created_at`: UTC timestamp

## Server rules
- The server applies each `operation_id` at most once. Replays return the original result.
- The server emits a monotonic sync cursor for pull.
- Deletes are tombstones. Tombstones are kept until safe compaction.
- Same-field concurrent edits produce a conflict record that keeps both versions. No silent last-write-wins.

## Failure cases and required behavior
| Case | Required behavior | Owner |
|---|---|---|
| Offline restart | Outbox survives restart; nothing is lost | Phase 2 |
| Duplicate operation replay | Applied once; second response matches the first | Phase 3 |
| Both devices edit the same field | Conflict record keeps both versions; no overwrite | Phase 3 |
| One device deletes a parent | Children are handled explicitly; no orphans, no silent delete of edited children | Phase 3 |
| Client clock drift | Ordering uses server revisions and cursors, not device clocks | Phase 3 |
| Expired token | Operations stay queued; re-authenticate; no data discarded | Phase 3 |
| Out-of-order pagination | Pull resumes from the last applied cursor; no duplicates or gaps | Phase 3 |

## Client invariants
- Local writes always succeed offline and are durable before the UI confirms them.
- The client never holds the service-role key.
- Task trees reject self-parenting, cross-workspace parents, and cycles.
