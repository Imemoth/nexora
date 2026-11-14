# Phase 3 S5: SQLite outbox v2 (planning baseline, reconciled)

**Status update (2026-11-14): S5 is implemented and in use (schema v2, later v3) and Phase 3 is accepted for the TEST environment. This document is the design baseline; current status is in `docs/coordination/status-register.md`.**

| | |
|---|---|
| Status | **Implemented locally (2026-11-12, owner authorization "Phase 3 S5 Complete Implementation").** SQLite schema v2, migration, backup, outbox, patches, folding, acknowledgement, conflict mirror and recovery are in `lib/features/tasks/data/`; evidence, deviations and open integration points: `docs/operations/s5-implementation-record.md`. Synchronization stays disabled: no transport, no pull, no authentication. |
| Source | The corrected Session B specification ("Phase 3 S5: corrected specification, acceptance, and implementation handoff"), supplied by the owner on 2026-11-12 as text and **received and reconciled on that date**. The earlier reconstruction in this file is replaced. |
| Authority | The Session B report was a proposed technical specification. The owner's authorization of 2026-11-12 ("Phase 3 S5 Complete Implementation") **approved proposals P-1 to P-8 as the implementation baseline with sixteen stated requirements**, which also confirm the [R] items; the tags below remain to show where each rule came from, and every one of them is now approved. Original tag legend: every rule carries a tag: **[A]** approved by an owner direction recorded in `status-register.md` (OD-x); **[R]** stated as approved policy inside the Session B report but recorded in no owner message in this repository, so it needs confirmation; **[P]** proposed by the report, needs owner approval. Where the tag is missing the line is a description of existing behavior. |
| Verification | The report's scratch checks (Python SQLite 3.50.4) were reproduced on SQLite 3.53.1 for the DDL and then re-run as Dart tests on the pinned `sqlite3` 3.9.1 bundle in Windows CI (blockers B-17, B-18 resolved; see `docs/operations/s5-implementation-record.md`). |
| Related | `docs/operations/s5-migration-safety-test-spec.md` (tests), `docs/architecture/s2-wire-contract.md` (server contract), `docs/coordination/status-register.md` (decisions, blockers), CR-2A-001 `phase-2a-sync-requirements.md` (original requirements REQ-1..8). |

## 1. Policy
| Policy | Tag |
|---|---|
| Payload 224 KiB per operation; batch 896 KiB and at most 100 operations, subject to exact S2 envelope verification | [R] |
| Unknown legacy rows stay unclassified and never sync; demo rows and their descendants are local-only | [R] |
| Dependent operations wait for predecessor acknowledgement | [R] (consistent with plan 4.3) |
| An absent patch key means unchanged; an explicit `null` clears a nullable field | matches the S2 wire contract |
| Terminal rejections preserve local data and need an explicit recovery action; recovery uses a **new** `operation_id` | [A] OD-5 |
| A backup is mandatory and **never deleted automatically**; retention is owner-controlled | [A] OD-8 (retention itself: O-10 open) |
| `completed_at` consistent with `status` is required; hosted enforcement needs separate authorization | matches O-1 (open) |
| Tree-delete server atomicity is deferred to the S3 gate | [R] |
| v1 to v2 order is the verified v1 `rowid` order, not `created_at_utc` | [A] OD-7 |
| Ambiguous historical outbox states are preserved without automatic replay, version reset or loss | [A] OD-9 |

## 2. Three base concepts, rule R, folding
| Concept | Column | Set when | Changed by |
|---|---|---|---|
| Observed base | `observed_base_version` | operation creation (first unsent edit); create = 0 | never (not by pull, acknowledgement or claim) |
| Wire base | `base_version` | claim time (`pending` to `in_flight`) | only rule R, before claim; frozen after claim |
| Transmitted payload | `payload_json`, `payload_bytes`, `op_type`, `entity_id`, `operation_id`, `base_version` | creation | immutable once `in_flight` (trigger-enforced) |

**Rule R [P] (dependency-adjusted wire base).** For an update or delete F whose predecessor P on the same entity is applied: set `wire_base(F) := P.applied_version` only if `P.version_before == observed_base(F)`; otherwise `wire_base(F) := observed_base(F)`. `version_before` is the server version immediately before P was applied. If the condition fails the observed base is kept: that can produce a false conflict but never suppresses one.
Proof (as in the report). The S1 guard sets `version := old + 1` on each changing update; a no-op leaves the version unchanged. Let V = `observed_base(F)` and A = `P.applied_version`. If `P.version_before == V` the only server change in (V, A] is P's own step: fields P wrote have `field_versions = A` (no false conflict) and every other field has `field_versions <= V < A` (no missed conflict). If `P.version_before > V` another device changed the entity after F's basis; keeping V makes every changed field with a different value a conflict.
Counterexample to the **naive rule** "always rebase to the predecessor's applied version": V = 3; device B changes `notes` at v4; P changes `title` and applies at v5 (`version_before` = 4); F edits `notes` with base 3. Naive rebase to 5 gives `field_versions[notes] = 4 <= 5`, suppressing the conflict and overwriting B's change. Rule R sees `version_before` 4 not equal 3, keeps base 3 and detects it. Also rejected: "rebase to the stored version at claim" (after a pull it hides conflicts on every pulled field).
**Consequence for older documents.** Plan 4.3, CR-2A-001 section 2 and `data-contract.md` row 3 say the engine "rewrites `base_version` from the previous acknowledgement". That wording is the naive rule and is **superseded by rule R**; those lines are annotated. Server prerequisite: `version_before` on applied results is **implemented locally in S2** (OD-6, not hosted); until it reaches hosted, rule R stays disabled and same-field dependent edits produce false conflicts (safe). Evidence that the server increments by exactly 1 per changing update: `supabase/tests/s2_contract_test.sql` (`vb_*`). A server test pinning the increment must stay in the suite (risk 4).
**Folding (pending updates only) [P].** A new edit merges into a pending operation only if the stored version still equals that operation's observed base; if a pull advanced it, a new dependent operation is created. (Trivially true in S5-only code; recorded for S6.)

## 3. Terminal states and recovery [P unless tagged]
- `applied` and `rejected` are terminal; payload and result are immutable. `conflict` is terminal for the operation. Resolution is recorded only in `sync_conflicts_local` (evidence columns immutable; resolution columns written once). Resolution never changes an operation's state; it may create a new operation with a new `operation_id`.
- Held successors of a conflicted operation do not become claimable through the old operation's state. A resolution action releases the dependency; each held successor keeps its observed base (the server decides) or the user archives it; default "keep" (S4 action).
- Rejections are recorded permanently by S2 under the `operation_id` [A OD-5], so recovery always uses a new `operation_id`; the old operation stays `rejected`. Two explicit actions: **resubmit** (new operation, observed base = last known server version) and **discard local** (restore fields from the last known server snapshot; archive pending work first; send nothing). Both need a `sync_entity_snapshot` table (new in v2) holding the last server row from an applied or conflict result or a pull.

## 4. Claim rule [P]
An operation is claimable only if: it is `pending`; every earlier operation on the same entity is `applied`; its `depends_on` predecessor is `applied`; and the entity has no open conflict or rejection. No same-batch dependencies. A child create waits for its parent's create to be applied.

## 5. v1 to v2 migration classification [P]
Each entity is classified by its v1 outbox history.
**Class S (synchronized, automatic)** only if all hold: at least one v1 `upsert` with base 0 in `pending`; no v1 operation in `sent`, `acked` or `failed`; no delete; no base > 0; its parent and project are also class S. Actions: local `version` becomes 0 (the only automatic version change; justification: no shipped build transmits anything, v1 has no network code, no `sent` writer and no `acked` writer, so a pending create never reached the server); the first pending create becomes the live create operation keeping its `operation_id`; later pending base-0 upserts are folded into it (archived `folded_into_create`), the payload being the last unsent full row; if that differs from the current row the entity drops to class U (warning W05), never silently sent.
**Class U (unclassified, never synchronizes).** Everything else: no create operation, `sync_scope = 'unclassified'`, version kept verbatim (no reset), all v1 operations archived verbatim, children of a U entity are U.
**Legacy states.** `sent`, `failed` and `acked` (none can come from shipped builds) make the entity class U; the operation is archived verbatim and never transmitted or inferred as applied; the domain row keeps its values. This is the report's answer to S5-Q1 and meets OD-9 (preserve, no replay, no version reset, no loss).
**Demo rows.** v1 has no marker, so v1 demo rows become class U; relabeling to `local_only` is an explicit owner action (O1), never an inference.
**Still aborts (file untouched, exact code):** unknown `user_version`; integrity failure; binding mismatch; a title over 200 characters (aborts, never truncates); foreign-key violation; post-migration digest mismatch; row-count mismatch.
**Removed from the report's earlier draft:** the blanket "reset every non-acked version to 0", "abort on base > 0", "abort on fold mismatch".
**Ordering [A OD-7].** The order of v1 outbox rows is the verified v1 `rowid` order. `sync_outbox` in v1 is an ordinary rowid table (TEXT primary key, no `WITHOUT ROWID`), so `rowid` is the insertion order the repository wrote; `created_at_utc` is the device clock and can go backwards. The order is read from the original file inside the migration transaction, never from a backup copy, and the snapshot digest must include rowid order. The report does not state a sequence-assignment rule of its own; OD-7 applies.
**Version-0 point.** Storing 0 for never-synchronized rows resolves Phase 2A's D-1 "stored version of a pending create" in favor of 0. That is a **proposal** (Phase 2A implemented `1` with the base derived from the outbox; the v1 `version > 0` CHECK also forbids 0, which the v2 rebuild would have to relax). It is not decided until the owner approves (S5-Q2).

## 6. Backup under lock [P, with OD-8 and OD-7]
1. Connection A: `PRAGMA foreign_keys=OFF`, then `BEGIN IMMEDIATE` (blocks other writers; WAL readers unaffected).
2. Inside A: read-only checks and the snapshot digest D_A (including rowid order, OD-7).
3. Connection B, no transaction: `VACUUM INTO '<partial>'` (reads the same committed snapshot; A has written nothing yet).
4. Open the partial read-only; require `quick_check = ok`, `user_version = 1`, digest = D_A; then rename to the final name. Never overwrite; never delete. A failed verification is renamed `.failed` and kept.
5. A: apply the v2 steps, `foreign_key_check`, set `user_version = 2`, `COMMIT`, then `foreign_keys = ON`.
Reconciliation with C1: SQLite may renumber rowids of tables without an explicit `INTEGER PRIMARY KEY` under `VACUUM`, so a `VACUUM INTO` copy is **not** a source of order. That is safe in this design because the order comes from A, and the digest check (which includes rowid order) fails if the copy's order differs. The earlier recommendation to prefer the online backup API is **withdrawn in favor of the report's verified design**, on the condition that the digest covers rowid order. Reported scratch result: backup digest equals the locked snapshot digest; a concurrent writer gets `database is locked`; the backup is still v1 after migration (reported, not reproduced here).

## 7. Pre-commit rollback and post-commit recovery [P]
Pre-commit: on error `ROLLBACK`; a crash is discarded by WAL; `user_version` stays 1; the backup is kept (verified or `.failed`); the migration reruns on the next open. Post-commit: v2 is durable; only these follow: `foreign_keys = ON` per connection, the migration report (a failure is retried and has no schema effect), requeue of `in_flight` rows (idempotent). A post-commit invariant failure pauses sync and surfaces an error; the only recovery is an owner-authorized restore from the verified backup. A committed migration is never rolled back automatically.

## 8. Schema-level invariants (as reported; to be re-verified on Dart sqlite3 3.9.1) [P]
CHECKs: a create has base 0 and observed base 0; update/delete with base 0 needs `depends_on`; a transmitted non-create has base >= 1. Partial unique indexes: `sync_one_inflight` (one in-flight per entity), `sync_one_live_create`. Triggers: identity immutable (operation id, entity, op type, observed base); claimed payload and base immutable; legal transitions only (`pending` to `in_flight`; `in_flight` to `pending`/`applied`/`conflict`/`rejected`); no delete of non-pending operations; archive append-only; `tasks.project_id` immutable. CHECKs on the `sync_state` singleton and the conflict resolution pair; FK `depends_on_seq` to `sync_outbox(seq)`; 12-step rebuild with `foreign_key_list(tasks)` targeting final names and an empty `foreign_key_check` before commit; a rebuild with a 300-character title aborts and rolls back fully. **Reported as not yet exercised** and required before any v2 step: `AUTOINCREMENT` non-reuse of `seq`, the conflict-evidence immutability trigger, the composite FK rejecting a child whose parent is in another project, the transmitted non-create base >= 1 CHECK (defined, not separately exercised), and the Dart runtime's SQLite version.

## 9. Tree delete [R/P]
The S2 contract applies each operation in its own sub-transaction with no group id, so a leaf-first chain is not atomic: if the parent delete conflicts after child deletes succeed, the child tombstones are irreversible (D-T). Plan 4.3 ("sends tombstone ops leaf-first in one push") and CR-2A-001 REQ-6 assume the chain is safe; **they are held until the S3 gate** and annotated. Until then S5 would refuse locally to delete a task that has live children (a repository precheck, not a server change) and restrict `softDeleteTask` to leaf rows **[P: needs owner authorization]**. When the gate opens, the chain is enqueued in one transaction, each child delete depending on the previous one and the parent on the last child, which is safe only with atomicity or an accepted partial outcome.

## 10. `completed_at` [P]
Rule: `done` if and only if `completed_at` is non-null; other statuses null; `archived` maps to null (**assumption, owner to confirm**). The client derives it from state, never from input, and includes it in the patch whenever it changes. This is compatible with the server-side Option A in the wire contract (the client supplies both fields; the server validates). S2 accepts any value today; hosted enforcement needs separate authorization (O-1).

## 11. Payload and batch size [R, bound to verify]
Per operation: `payload_bytes` = UTF-8 bytes of the exact JSON sent, ceiling 229,376 (224 KiB), refused before any write (the draft stays in the editor). Batch: count <= 100; sum of `payload_bytes` <= 917,504 (896 KiB); and sum of (`payload_bytes` + 512) <= 1,000,000. The 512-byte per-operation envelope estimate is **to be measured against `p_ops::text`** (blocker B-19); the server's hard bounds are 262,144 bytes per patch (`payload_too_large` per operation) and 1,048,576 bytes per call (`NX004`). Both ceilings leave headroom below the server limits. These client limits are independent of the unresolved response-size bound D-RESP (O-2).

## 12. Tests
S5-0 (done, see the safety spec): golden v1 text/hash and schema fingerprint, synthetic v1 fixture, domain/outbox failure injection. S5 (not started): see the safety spec matrix plus, from the report: rule R with the counterexample, class S/U migration, backup-under-lock, pre/post-commit, claim rule, folding, rejection recovery (resubmit, discard-local with archive), tree-delete precheck, results matched by `operation_id` with length and id-set check, payload ceilings, cross-process open (T-50), cryptographically secure operation ids.

## 13. Compatibility with the S2 wire contract (current state at head)
| Area | State |
|---|---|
| Request, operation keys, op types, base_version rules, patch null semantics, `client_created_at`, `request_id` (client-only) | compatible |
| Result statuses, `applied_version`, `row`, `replayed`, `auto_resolved` | compatible |
| **`version_before` on applied results (report: "needs S2")** | **implemented locally in S2 (OD-6); not hosted.** Enables rule R |
| **Conflict detail (report: "needs S2")** | **implemented locally**: `conflict.{kind, fields, base_version, server_version, server_value, client_value, status}` (report's `conflict_kind` is `conflict.kind`). The mirror columns follow the object |
| `blocked_by_conflict` recorded permanently as `rejected` | **open (O-11)**: the report asks whether it should be non-terminal (unrecorded, retryable after resolution). Today it is terminal; recovery is a resubmit with a new id (OD-5). Not changed without an owner decision |
| Conflict kinds | S1 allows `field, edit_deleted, delete_edited, parent_deleted, parent_has_live_children, cycle, exists`. S2 emits `field, exists, edit_deleted, delete_edited, parent_has_live_children` only; `parent_deleted` and `cycle` are not emitted (a tombstoned parent is `rejected: parent_invalid`, OD-4). The mirror accepts all S1 kinds |
| Results matched by `operation_id` (length and id-set check) | client rule; added to wire contract 3.1 |
| 8 s `statement_timeout` vs 100-operation batch; 512-byte envelope | to measure (B-9, B-19) |
| Delete | tombstone, already-tombstoned no-op, live-children conflict, `delete_edited`; not atomic across a chain (section 9) |

## 14. Reconciliation of the report's R-1 to R-15 with the repository
R-1 (three base concepts) adopted as [P]. R-2 (only class S becomes 0) adopted; consistent with OD-9. R-3 (conflict terminal for the operation) adopted. R-4 (lock, then backup) adopted; reconciled with OD-7 (section 6). R-5/R-6 (class U instead of abort) adopted. R-7 (S2 requires base >= 1 for update/delete, so the delete waits for the create's acknowledgement) agrees with the wire contract. R-8/R-15 (delete is in S2 minimally; chain atomicity is the S3 gate) agrees. R-9 (only S1 conflict kinds) agrees (section 13). R-10 (`notes` is `TEXT NULL` in v1, map with `COALESCE(notes,'')`) agrees with the shipped v1 DDL. R-11 (`request_id` client-only) agrees. R-12 (8 s timeout) agrees with the wire contract. R-13 (map by `operation_id`) added. R-14 (stale comments): `migrations.dart` corrected in S5-0; the three `sqlite_task_repository.dart` comments are **not yet changed** (code comments, outside the documentation gate).

## 15. Open points and owner decisions
| # | Point | State |
|---|---|---|
| S5-Q1 | Representation of preserved v1 `sent`/`failed`/`acked` rows | **decided**: class U, verbatim archive (authorization requirement 5) |
| S5-Q2 | Stored version of a pending create | **decided**: 0 for demonstrably never-synchronized entities (requirement 4); v2 relaxes the CHECK to `version >= 0` |
| S5-Q3 | Title CHECK 500 locally vs 200 on the server | **decided**: 200 (requirement 9); migration aborts, never truncates |
| S5-Q4 | Owner binding column name | **decided**: `meta.user_id` (requirement 9) |
| S5-Q5 | `request_id` | **decided**: client-side only, never sent (requirement 10) |
| S5-Q6 | Per-entity `sync_scope` flag | **decided**: explicit `sync_scope` (`synced`, `local_only`, `unclassified`), no default |
| O-11 | `blocked_by_conflict` terminal or retryable | **decided**: stays a recorded terminal rejection (requirement 13); recovery is a resubmit with a new id |
| O-12 | Delivery route | **decided**: the existing Phase 3 branch |
| O-13 | Local tree-delete precheck | **decided and implemented** (requirement 14) |
| O-14 | `archived` maps to null `completed_at` | **decided and implemented** (requirement 16) |
| O-15 | Real-database handling | **decided**: unclassified entities never synchronize automatically (15); demo records and descendants stay local-only (6); relabeling legacy demo rows is a manual owner action and is not implemented |

## 16. Remaining risks (from the report, unchanged unless noted)
1 Backups are plaintext copies of titles and notes accumulating in the app data folder; retention is an owner decision (OD-8: never automatic). 2 Tree delete is non-atomic on the server; the local precheck is the only protection until the S3 gate and must be tested. 3 Conflict detail: now provided by S2 (locally); do not show "resolved" without evidence. 4 Rule R relies on `version_before` and the exact +1 increment. 5 Recorded rejections need a visible recovery UI. 6 Discard-local can erase intent: archive first, never delete. 7 Unclassified and demo rows must never sync; the `sync_scope` default must be reviewed. 8 Two app instances: cross-process test. 9 A backup at a disk-full or antivirus-locked moment leaves a partial file (kept, never deleted). 10 Migration diagnostics contain ids and counts only. 11 `completed_at` is device time. 12 Operation ids must come from a secure generator (`RandomIdGenerator` not verified). 13 D-U anonymous sign-in unaudited; the binding must reject anonymous ids. 14 `nexora_private` exposure must be verified on the hosted project before any S2 hosted apply. 15 The local database is unencrypted (out of scope).
