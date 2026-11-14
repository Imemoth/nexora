# Phase 3 S5 implementation record (2026-11-12)

**Note (2026-11-14): this record describes the state at the time it was written. Statements such as "not applied to hosted", "disabled" or "not run" are historical; the hosted TEST deployment and Phase 3 acceptance are recorded in `docs/operations/hosted-acceptance-record-2026-11-13.md` and the current status is in `docs/coordination/status-register.md`.**

**S5 (SQLite schema v2 and the outbox) is implemented locally and passes Windows CI. Synchronization is not active: there is no transport, no pull, no authentication, and nothing was written to the hosted project.** Authority: owner authorization "Phase 3 S5 Complete Implementation" (decision OD-11 in `docs/coordination/status-register.md`). Specification: `docs/coordination/phase-3-s5-outbox-v2.md`. Tests mapped in `docs/operations/s5-migration-safety-test-spec.md` section 5.

## What was built
| Spec item | Code (`lib/features/tasks/data/`) | Evidence (`test/features/tasks/data/`) |
|---|---|---|
| Forward-only migration v1 to v2 in one write-locked transaction, foreign keys off, post-checks | `migration_v2.dart`, `local_database.dart` | `migration_v2_test.dart` |
| Verified backup under lock; never overwritten or deleted | `migration_v2.dart` (`VACUUM INTO` on a second connection, digest taken under the lock, `.failed` rename), `snapshot_digest.dart` | `backup`, `concurrency` groups |
| Classification: class S (version 0, live create, folding) and class U (unclassified, verbatim archive) | `migration_v2.dart` | `classification` group |
| v1 rowid order, not `created_at_utc` | `migration_v2.dart` (`ORDER BY rowid`, creates inserted in that order) | ordering test (timestamps run backwards) |
| Schema v2, indexes, triggers, explicit `sync_scope` (no default), 200-character titles, `meta.user_id` | `schema_v2.dart`, `local_storage.dart`, `LocalDatabase.bindUser` | `v2 schema` group |
| Outbox ordering (`seq` AUTOINCREMENT), lifecycle, immutable transmitted operations, append-only archive | `schema_v2.dart` (CHECKs, partial unique indexes, triggers) | `v2 schema` group |
| Field-level changed-only patches; folding into a pending, never-claimed operation | `sqlite_task_repository.dart`, `outbox_store.dart` (`recordEdit`) | `repository behaviors`, `outbox` groups |
| Dependent operations wait; claim rule; no same-batch dependencies | `outbox_store.dart` (`claimBatch`, `_claimableSql`) | `claim rule and dependencies` group |
| Rule R, frozen wire base, retries send the identical operation | `outbox_store.dart` (`computeWireBase`, `claimBatch`) | `rule R`, `rule R in operation` groups; `outbox_property_test.dart` (40 seeds against a fake server implementing the S2 conflict rule: no overwrite of another device's change; one in flight; payload frozen; retry identical) |
| Payload ceiling 224 KiB, batch 100 operations and 896 KiB, exact serialized envelope check | `outbox_store.dart`, `jsonb_size.dart` | claim tests; `jsonb_size_test.dart`; the size function matched PostgreSQL's `jsonb::text` byte count on 40 random batches (local PostgreSQL 16, Unicode and escapes included) |
| Acknowledgement by `operation_id` with count and id-set check, atomic per call | `outbox_store.dart` (`acknowledge`) | `acknowledgement` group |
| Local conflict mirror (evidence immutable, resolution written once) and authoritative snapshots | `schema_v2.dart`, `outbox_store.dart` | `conflicts` group |
| Rejected operations immutable; recovery with a new `operation_id` (resubmit, discard local after archiving) | `outbox_store.dart` | `rejections` group |
| Crash and restart recovery (`in_flight` back to `pending`, frozen) | `outbox_store.dart` (`recoverInFlight`), `main.dart` | `crash and restart recovery` group |
| Local-only demo data and descendants; unclassified entities never produce operations | `sqlite_task_repository.dart` | `repository behaviors` group |
| `completed_at` derived locally (non-null only while done, null for archived) | `sqlite_task_repository.dart` | `repository behaviors` group |
| Tree deletion refused while live children exist | `sqlite_task_repository.dart` | `repository behaviors` group |
| Migration diagnostics: ids and counts only | `migration_v2.dart` (`sync_migration_report`) | diagnostics test |
| Device id created once and persisted | `outbox_store.dart` (`deviceId`) | crash and restart group |
| Windows SQLite runtime | the whole suite on the pinned `sqlite3` 3.9.1 | Windows CI |

## Existing tests changed because their meaning changed
New entities store version 0; an edit before the first send folds into the pending create (so no second operation); a fresh file is created at v1 and migrated to v2; the S5-0 golden test now compares the frozen v1 statements on a plain database (the v1 text and hash tests are unchanged); the failure-injection test also injects on `UPDATE` because an edit now updates the pending operation.

## Test evidence
Windows CI run [43283204393](https://github.com/Imemoth/nexora/actions/runs/43283204393) on code head `7a20b4d`: format, `flutter analyze`, the full `flutter test` suite (see the final report for the count), the cross-process SQLite restart check and the release build. PostgreSQL 17 and documentation CI results for the final head are in the final report. The repository documentation consistency check (`tools/check_docs.py`) runs in `docs-check`.

## Decisions taken inside the authorization (routine engineering)
- Backup files sit next to the database as `<name>.pre-v2.bak` (`.1.bak`, `.2.bak` when one exists); a partial copy is `.partial` and a failed verification is renamed `.failed`. Nothing is overwritten or deleted. Where backups live and when a person removes them stay owner decisions (O-10).
- The snapshot digest is a 128-bit FNV-style checksum over a fixed table order; it detects row, content and **order** differences, not rowid values (SQLite may renumber rowids in a copy). It is an integrity check, not a security feature.
- Rule R has one addition to the report: an observed base of 0 (the operation was queued behind an unacknowledged create) takes the predecessor's applied version, because the wire requires a base of at least 1.
- A conflict or rejection is "handled" by a write-once `handled_at_utc`; handled operations release their successors. A resubmit is a new operation with a higher `seq`, so successors queued earlier go first (both are safe, the server merges field by field).
- `ownerIdOf` reads and creates `meta.user_id`; the repository does not bind implicitly, `LocalDatabase.bindUser` refuses a second user explicitly.
- A result whose `conflict` detail is incomplete is still mirrored (unknown kind becomes `field`, missing values are empty objects) so no conflict is lost.
- Snapshots come from acknowledgements and conflict results only; a snapshot never moves to an older server version. The `pull` source value is reserved for S4.

## Not implemented (outside S5)
Sync transport and engine (S6), pull and cursor (S4), server resolve and delete atomicity (S3), authentication and secure storage (S7), user interface for the recovery actions, relabeling legacy demo rows to `local_only` (a manual owner action), backup retention policy (O-10), hosted deployment of S2 (O-9).

## Remaining S2/S5 integration issues
1. **`version_before` and `conflict` detail exist only in the local S2 migration.** Rule R and the conflict mirror depend on them; the hosted project has neither until S2 is deployed under its own gate.
2. **`blocked_by_conflict` is terminal** (decided). The S6 engine must offer resubmit after a conflict is resolved; there is no server-side resolve until S3.
3. **`completed_at` rule is not enforced on the server** (O-1). The client derives consistent values; a server that accepts anything is unchanged.
4. **Tree delete** is refused locally while live children exist; the leaf-first chain is enqueued only after the S3 atomicity protocol.
5. **Hosted limits are unmeasured**: the 8 s `statement_timeout` against a 100-operation call, and the real `p_ops` call limit on the hosted project (B-9). The client stays well below the 1,048,576-byte limit (it stops at 1,000,000 bytes of exact serialized size and 896 KiB of payload).
6. **The user's real database** must be migrated from a copy first; the migration writes a verified backup, but shipping v2 to users is a release decision that is not authorized here.
7. **`request_id`** is stored per attempt in the outbox and never sent; S2 has no server meaning for it.
8. Conflict kinds `parent_deleted` and `cycle` are accepted by the mirror but S2 does not emit them.

## Next package
S6: the Dart sync engine against a fake transport, on top of `OutboxStore` (`claimBatch`, `acknowledge`, `releaseClaims`, `recoverInFlight`, the recovery actions), with backoff, ordering, and the error taxonomy of the wire contract (section 3.1). In parallel on the server side: S3 (resolve and delete atomicity) and S4 (pull), which S6 needs before any activation.
