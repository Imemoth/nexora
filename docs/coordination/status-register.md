# Nexora status register (single source of truth)

Last updated: 2026-11-16 (Phase 5 implementation and follow-up fixes on `feature/phase-5-ui-ux`; Phase 4 merged as PR #18). **This file is the only place that states current phase and slice status, migration history, owner decisions with their approval status, gates and blockers.** Other documents describe design or evidence and link here; where another document disagrees with this register, this register is correct unless it cites that document as the exception. The documentation map is `docs/README.md`.

**Permanent environment rule: `docs/development-environment-policy.md`.** Nexora is DEVELOPMENT/TEST only; no production environment exists; the Supabase project `uicccaawtjvqggeufbez` is DEV/TEST and all its data is mock or test data. Statements below about production, hardening, release candidates, rollback or legacy compatibility are deferred background or optional guidance, not current requirements; hosted writes and destructive actions still need the owner's separate authorization of the exact operation.

Rules: (1) a recommendation is not an approval; only entries marked **approved** are decisions; (2) "implemented" requires an evidence path (section 7); (3) hosted changes happen only with explicit owner authorization.

## 1. Phase and slice status
| Item | Status | Evidence / note |
|---|---|---|
| Phase 0 foundation | Done, on `main` | `docs/superpowers/plans/2026-11-11-nexora-phase-0-foundation.md`; Supabase access gate PASS (`docs/operations/supabase-access.md`) |
| Phase 1 desktop UI | Accepted by the owner, on `main` (PR #12) | `docs/operations/phase-1-acceptance.md` |
| Phase 2A local SQLite | **Merged into `main` (PR #13).** Owner-completed Windows acceptance SAVE-PERSIST-01 recorded | `docs/operations/phase-2a-windows-acceptance.md`; REQ-1, REQ-7 implemented; REQ-2, 3 (payload), 4, 6 open (S5) |
| Phase 2B Supabase foundation | **Applied to hosted** (3 migrations) and verified; accepted | `docs/operations/phase-2b-apply-record.md` |
| F1 guard_row fix | **Applied to hosted** as `20261112142732` | `docs/operations/f1-hosted-fix-record.md` |
| S0 contract freeze | Done (docs) | `docs/architecture/data-contract.md`, ADR 0002 |
| S1 protocol schema | **Applied to hosted** as `20261112151851` and verified (rollback-only suites, advisors, empty tables) | `docs/operations/s1-hosted-deployment-record.md` |
| S2 push RPC | **Applied to the hosted TEST project on 2026-11-13 (`20261113084613`) and accepted over real HTTP/JWT.** | `docs/operations/hosted-acceptance-record-2026-11-13.md` |
| S3 resolve, revoke, atomic tree delete | **Applied to the hosted TEST project on 2026-11-13 (`20261113085005`) and accepted over real HTTP/JWT.** | same record |
| S4 pull and cursor | **Applied to the hosted TEST project on 2026-11-13 (`20261113091105`) and accepted over real HTTP/JWT.** | same record |
| S5 SQLite outbox v2 | **Implemented and in use** (schema v2, later v3 for sync state): forward-only migration with verified backup, outbox state machine, rule R, folding, acknowledgement, conflict mirror, snapshots, recovery actions, local-only demo data. Tested on Windows CI; exercised in the manual Windows acceptance. | `docs/operations/s5-implementation-record.md`, `docs/coordination/phase-3-s5-outbox-v2.md`, `docs/operations/s5-migration-safety-test-spec.md`, `test/features/tasks/data/` |
| S6 sync engine | **Implemented; active in the sync-enabled DEVELOPMENT TEST build** (`NEXORA_SYNC` build flag, default build OFF). Two-device end-to-end suite on disposable PostgreSQL 17; cross-device convergence confirmed on the hosted TEST project in manual acceptance | `docs/operations/s6-implementation-record.md`, workflow `e2e-sync` |
| S7 auth and session | **Implemented; accepted on the TEST project**: Supabase Auth client over `dart:io`, native in-process DPAPI session storage (PowerShell fallback), session manager (restore, refresh, expiry, revocation, anonymous rejection), per-account SQLite files, account-bound transport, runtime wiring, sign-in UI, bounded sign-in with diagnostics (hang fix) | `docs/operations/s7-s8-implementation-record.md`, `docs/operations/windows-signin-hang-fix-record-2026-11-13.md` |
| S8 end-to-end acceptance | **Done**: real HTTP/JWT suite on a disposable local stack (workflow `http-integration`), Windows-level acceptance suite (`test/s8/`), and the hosted TEST acceptance over real HTTP/JWT (2026-11-13) | `docs/operations/s7-s8-implementation-record.md`, `docs/operations/hosted-acceptance-record-2026-11-13.md` |
| S9 removal of direct table-write grants | **Applied to the hosted TEST project on 2026-11-13 (`20261113094553`); direct writes refused over HTTP.** | `docs/operations/hosted-acceptance-record-2026-11-13.md` |
| Manual import of local data | **Implemented**: explicit, preview-first, per-record import into the signed-in account (O-16 resolved); user-initiated project creation (no automatic default project in account workspaces, O-17 resolved) | `docs/operations/release-candidate-guide.md` |
| Conflict resolution UI | **Implemented**: actionable indicator, conflict list, side-by-side comparison, valid strategies with confirmation, failure handling, restart and end-to-end tests | `docs/operations/conflict-resolution-ui-record-2026-11-13.md` |
| Synchronization and Auth activation | **Active only on the TEST project and in the sync-enabled DEVELOPMENT TEST build.** The default build keeps `NEXORA_SYNC` OFF. No production users, no production project | section 4 |
| **Phase 3 (sync, auth, conflicts)** | **Accepted for the current TEST environment** on the owner's manual Windows acceptance (owner statement 2026-11-14): authentication and session restoration; local data import; automatic bidirectional synchronization; offline editing and automatic recovery; conflict detection; interactive conflict resolution (final CONFLICT-A / CONFLICT-B test resolved with B, applied value confirmed in the hosted database and received by device A); cross-device convergence | `docs/operations/hosted-acceptance-record-2026-11-13.md` plus the owner statement (the manual acceptance has no separate repository record) |
| **Phase 4 (Windows reminders, system tray, notifications)** | **Accepted for the current TEST environment** on the owner's manual Windows acceptance (owner statement 2026-11-14; all six checks passed: reminder creation and notification delivery; minimize to system tray; notification click opens the correct task; snooze, acknowledge and reschedule; reminder persistence without duplicate notifications; single-instance behaviour). Implemented on the development branch; **integration PR to `main` awaiting owner approval** | `docs/operations/phase-4-implementation-record-2026-11-14.md` |
| Task reminders | **Implemented, device-local** (D-RM): SQLite schema v4 table `task_reminders`, local wall-clock times with DST rules, restart-safe claim, missed handling, snooze, acknowledge, in-app reminder list; never synchronized; no hosted change | implementation record |
| Windows tray and notifications | **Implemented**: native runner code (tray icon, shell notifications, minimize to tray, single instance, tray Exit), Dart bridge `nexora/desktop` | implementation record |
| **Phase 5 UI/UX modernization (Midnight)** | **Implemented on `feature/phase-5-ui-ux` (from `main` at `bc12b30`); Draft pull request open; owner Windows acceptance pending; no merge.** Seven work packages: theme and fonts, workspace restyle, status/account/reminder surfaces, dashboard, status filter and quick add, delete task and project, tests and docs. No hosted change, no schema change. **Next build 1.1.0+2** (sign-in and synchronization DEVELOPMENT TEST build, synchronized optional due times, default expansion of parents, reveal path for related subtasks, parent emphasis, Project-first New task): implemented and tested locally; **hosted due-time migration awaits owner approval** (`docs/operations/due-time-hosted-migration.md`); until it is applied the client keeps the time switched off while signed in. **Follow-up fixes on the same branch** (stale UI after sync, due time, reminder dialog, subtask parent, search/focus/panels, startup window, About and build identity): implemented and tested on Linux, **Windows native code not yet compiled or run, goldens must be regenerated on Windows, Windows follow-up checks not run**; synchronized due time is **blocked on a hosted schema change that needs owner approval** (ADR 0004 section 6). **Live-acceptance round:** unsaved edits are now protected on title-bar X and tray Exit (cause and fix in implementation record section 10), plus panel-width memory, clearer hidden-task notice, picker limits, Notes-match excerpts, narrow-width readability and a second-launch foreground request; automated on Linux only, Windows checks F21 to F30 **not run**. | `docs/operations/phase-5-implementation-record-2026-11-16.md`, `docs/architecture/decisions/0003-phase-5-ui-ux.md`, `docs/operations/phase-5-acceptance.md` |

## 2. Migration history
| Repo file | Hosted version | State |
|---|---|---|
| (initial schema; applied through the Supabase connector, not stored in the repo; reproduced by `supabase/tests/00_bootstrap_local.sql` for local tests) | `20261112111349` `nexora_initial_domain_schema` | applied |
| `supabase/migrations/20261112115809_nexora_security_hardening.sql` | `20261112115809` | applied |
| `supabase/migrations/20261112120132_nexora_contract_alignment.sql` | `20261112120132` | applied |
| `supabase/migrations/20261112120149_nexora_sync_foundation.sql` | `20261112120149` | applied |
| `supabase/migrations/20261112125000_nexora_fix_projects_update_guard.sql` (F1) | `20261112142732` | applied (hosted timestamp differs from the file name) |
| `supabase/migrations/20261112130000_nexora_sync_protocol_schema.sql` (S1) | `20261112151851` | applied; SHA-256 `cb947073...5d42e2`, rollback `97f5e738...8596` |
| `supabase/migrations/20261112160000_nexora_sync_push.sql` (S2) | `20261113084613` | **applied to the hosted TEST project on 2026-11-13**; rollback `supabase/rollback/20261112160000_rollback_s2_sync_push.sql` |
| `supabase/migrations/20261112170000_nexora_sync_resolve_revoke.sql` (S3) | `20261113085005` | **applied to the hosted TEST project on 2026-11-13**; rollback `supabase/rollback/20261112170000_rollback_s3_resolve_revoke.sql` |
| `supabase/migrations/20261112180000_nexora_sync_pull.sql` (S4) | `20261113091105` | **applied to the hosted TEST project on 2026-11-13**; rollback `supabase/rollback/20261112180000_rollback_s4_sync_pull.sql` |
| `supabase/migrations/20261112185000_nexora_sync_throttle.sql` (S10a) | `20261113091345` | **applied to the hosted TEST project on 2026-11-13**; per-user throttle (NX007); rollback `supabase/rollback/20261112185000_rollback_sync_throttle.sql` |
| `supabase/migrations/20261112186000_nexora_sync_response_bound.sql` (S10b) | `20261113091606` | **applied to the hosted TEST project on 2026-11-13**; push-response bound (NX004); rollback `supabase/rollback/20261112186000_rollback_sync_response_bound.sql` |
| `supabase/migrations/20261116100000_nexora_due_time.sql` (optional due time) | **not applied** | **proposed, awaiting the owner's separate approval of this exact file** (digests, sequence, verification, rollback and old-client policy: `docs/operations/due-time-hosted-migration.md`); additive; rollback `supabase/rollback/20261116100000_rollback_due_time.sql`; verified on a disposable local PostgreSQL only |
| `supabase/migrations/20261112190000_nexora_s9_revoke_direct_writes.sql` (S9) | `20261113094553` | **applied to the hosted TEST project on 2026-11-13**; revokes direct table writes, keeps SELECT; rollback `supabase/rollback/20261112190000_rollback_s9_direct_writes.sql`; applied last in the combined operation |
Hosted history was read read-only on 2026-11-12 (the first six rows). After the 2026-11-13 operation the hosted history is the first six rows plus the six rows above, in this order, with the stamped versions shown; function bodies were verified identical to the repository files. Local migration files were editable only while unapplied; applied files are frozen. **No further hosted migration is authorized.**

## 3. Owner decision register
Status: **approved**, **conditional** (approved with the stated condition still open), **unverified**, **open** (needs a decision; any proposal is a recommendation only).
| ID | Decision | Status | Source / condition |
|---|---|---|---|
| D-C | Field-level conflict detection (`field_versions`) | approved | ADR 0002 |
| D-A | A conflicting operation applies nothing | approved | ADR 0002 |
| D-P | Leaf-first explicit delete, no cascade | approved | ADR 0002 |
| D-V | Local `version` is server-owned | approved | ADR 0002 |
| D-T, D-E | Permanent tombstones; update after delete is a conflict | approved | ADR 0002 |
| D-N | Notes conflict as a whole field | approved | ADR 0002 |
| D-D | At most 10 active devices | approved | ADR 0002 |
| D-X | Disposable PostgreSQL 17 CI; hosted tests rollback-only | approved | ADR 0002 |
| D-F | Build-time flag, default OFF | approved | ADR 0002 |
| D-L | Per-user advisory lock | conditional | multi-session tests with negative control and one lock for every write path: **met for S1/S2** (CI), re-check at each new write path |
| D-R | INVOKER wrappers over private DEFINER functions | approved (as built) | exact grants, `search_path`, ownership and non-exposure verified locally and on the hosted TEST project (acceptance record); Option A (no privilege change) is what is deployed |
| D-O | sort_order server-wins, auditable | conditional | **met in S1/S2** (DB-enforced audit; tests) |
| D-S | Client dependency architecture | approved in principle | exact versions and secure storage need review before S7 |
| D-U | Anonymous sign-in and public sign-up | **decided for the TEST environment**: public sign-up stays enabled during development; anonymous users are rejected by the client and by the protocol. A production Auth hardening review is a separate future step | `docs/operations/auth-dashboard-audit.md`, acceptance record |
| A-S1 | S0 and S1 on the dev branch; later hosted S1 apply | approved | owner messages "Phase 3 Owner Architecture Decision" and "S1 Hosted Deployment"; recorded in the S1 record |
| A-F1 | Standalone F1 hosted fix only | approved, done | f1 record |
| A-S2 | Implement S2 locally; no hosted S2 | approved, done locally | S2 record |
| OD-1 | S2 accepted as locally tested baseline, **not** hosted-ready | approved (direction 2026-11-12) | consolidation message |
| OD-2 | Corrected S5 specification is the planning baseline, subject to compatibility and migration-safety gates | approved (direction 2026-11-12); **the text is missing from the repository** (blocker B-3) | consolidation message |
| OD-3 | sort_order mixed-field update: server wins for `sort_order` only, other fields apply | **approved** (owner direction 2026-11-12, item 4) | wire contract 7 |
| OD-4 | Creation under a tombstoned parent is `rejected: parent_invalid` | **approved** (owner direction 2026-11-12, item 5) | wire contract 7; supersedes the plan's S3 `create_under_tombstoned_parent_conflicts` |
| OD-5 | Rejected operations are immutable history; recovery uses a new operation id | **approved** (owner direction 2026-11-12, item 3) | wire contract 2 |
| OD-6 | `version_before` in applied results; conflict detail for the S5 mirror | **approved** (owner direction 2026-11-12, items 1-2) | wire contract 2 |
| OD-7 | v1 to v2 outbox ordering uses the verified v1 `rowid` order, not `created_at_utc` | **approved** (owner direction, documentation reconciliation gate 2026-11-12, item 3) | S5 doc 3a C1; safety spec M2 |
| OD-8 | No automatic deletion of SQLite backups; retention is owner-controlled | **approved** (owner direction, same gate, item 4) | S5 doc 3a C2; safety spec section 2, M14 |
| OD-9 | Ambiguous historical outbox states (`sent`, `failed`) are preserved without automatic replay, version reset or loss | **approved** (owner direction, same gate, item 5); the v2 representation is open (S5-Q1) | S5 doc 3a C3; safety spec M3, M13 |
| OD-11 | P-1 to P-8 (the S5 baseline) approved for implementation with sixteen requirements: rule R; immutable transmitted operations; v1 rowid order; version 0 for never-synchronized entities; ambiguous history unclassified, no automatic replay; demo records and descendants local-only; dependent operations wait for acknowledgement; 224 KiB per operation and 896 KiB per batch with exact envelope checks; 200-character titles and `meta.user_id`; `request_id` client-side only; verified backup, never deleted automatically; rejected recovery with a new `operation_id`; `blocked_by_conflict` stays a recorded terminal rejection; no local tree deletion with live children until the S3 protocol; unclassified entities never synchronize; `completed_at` derived locally | **approved** (owner authorization "Phase 3 S5 Complete Implementation", 2026-11-12); implemented | S5 doc; implementation record |
| OD-10 | The corrected Session B report is a proposed technical specification, not an authorization of unresolved owner decisions; its backup-under-lock design, observed-base versus wire-base semantics, immutable operation history and conflict-resolution requirements are to be incorporated | **approved as direction** (same gate, items 1 and 6); **report received and incorporated 2026-11-12** (S5 doc, safety spec, wire contract, this register); the items inside it remain proposals until approved (section 3a) | S5 doc |
| D-RM | Task reminders are device-local: stored in the active workspace's SQLite file, never synchronized, stated in the details panel | **approved** (owner direction 2026-11-14: keep the device-local model for V1) | Phase 4 record |
| D-RW | A reminder time is a local wall-clock time resolved at evaluation (DST: skipped hour moves after the gap, repeated hour fires once at the first occurrence) | approved as built (accepted with Phase 4) | Phase 4 record |
| D-RX | Close button exits the app; minimize goes to the tray; tray menu has Open Nexora and Exit; no notification after the app has fully exited | approved as built (accepted with Phase 4) | Phase 4 record |
| O-1 | `completed_at`/`status` rule | **resolved as built**: Option A (validate only) | wire contract 7 |
| O-2 | Response size bound (D-RESP) | **resolved**: bound implemented and applied (S10b, NX004) | `docs/operations/hardening-implementation-record.md` |
| O-3 | Rate limiting and log retention/purge path | **partly resolved**: per-user throttle (S10a, NX007) applied; log retention and purge remain a production-hardening item, not in V1 test scope | security record R1-R3 |
| O-4 | Client device revoke RPC | **implemented locally** (`nexora_revoke_device`, S3); hosted use needs the S2/S3 gate | s3-s4 contract 3 |
| O-5 | `request_id` server meaning | open | recommendation: none; client-side only |
| O-6 | D-R Option A confirmation (no privilege change) | **resolved as built** (Option A deployed) | security record section 2 |
| O-7 (resolved by OD-11) | S5 open points S5-Q1 to S5-Q6 (representation of preserved legacy rows, stored version of a pending create, title limit, owner binding name, `request_id`, `sync_scope`) | open; the report supplies proposals for each | S5 document section 15 |
| O-11 | `blocked_by_conflict` | **resolved**: stays a recorded terminal rejection (OD-11) | wire contract 7 item 9 |
| O-12 (resolved: the existing branch; implemented) | Delivery route for the remaining S5-0 pieces (generated `.db` fixtures with manifests and SHA-256, 300-character-title fixture, duplicate-`operation_id` failure test, three `sqlite_task_repository.dart` comment corrections): this branch, or a new branch (needs explicit approval) | open | S5 safety spec, S5 doc 14 |
| O-13 | Local tree-delete precheck | **resolved and implemented** (OD-11) | S5 doc 9 |
| O-14 | `archived` maps to null `completed_at` | **resolved and implemented** (OD-11) | S5 doc 10 |
| O-15 | Real-database handling | **resolved** (OD-11): unclassified rows never sync; demo relabeling is a manual owner action and is not implemented | S5 doc 5 |
| O-16 | Local data and accounts: separate local and account database files; local data is never attached silently | **resolved and implemented**: explicit, user-initiated, preview-first import | release-candidate guide |
| O-17 | Default project of a new account | **resolved**: no automatic default project in account workspaces; project creation is user-initiated | release-candidate guide |
| O-18 | DPAPI through PowerShell versus a native store | **resolved**: native in-process DPAPI via `dart:ffi` (Crypt32, no new package), PowerShell kept as fallback | `docs/operations/windows-signin-hang-fix-record-2026-11-13.md` |
| O-8 | Scope and order of S3 and S4 | **resolved** by the owner authorization of 2026-11-12 (S3, S4 and S6 as one package) | s3-s4 record |
| O-9 | Hosted S2 gate approval | **resolved**: authorized and executed 2026-11-13 | acceptance record |
| O-10 | Backup retention for the local SQLite file before migration 2 (how long, who removes it). **Deletion is never automatic (OD-8).** | open | S5 safety spec section 2 |

### 3a. Proposals from the Session B report (awaiting approval; not decisions)
| ID | Proposal | Tag in S5 doc |
|---|---|---|
| P-1 | Three base concepts and the dependency-adjusted rule R (replaces the blind re-base in the plan, CR-2A-001 and the data contract) | [P] section 2 |
| P-2 | Claim rule (earlier operations and predecessor applied, no open conflict or rejection) | [P] section 4 |
| P-3 | Migration classification: class S (version 0, first create live, folding) and class U (never synchronizes, verbatim archive); this is also the proposed answer to S5-Q1 | [P] section 5 |
| P-4 | Backup under lock (`BEGIN IMMEDIATE`, `VACUUM INTO`, digest equality including rowid order, `.failed` rename, never overwrite or delete) | [P] section 6 |
| P-5 | Pre-commit rollback and post-commit recovery rules | [P] section 7 |
| P-6 | v2 schema invariants (CHECKs, partial unique indexes, immutability and state-machine triggers, `sync_entity_snapshot`) | [P] section 8; not exercised on Dart sqlite3 3.9.1 |
| P-7 | `completed_at` derived by the client from `status`; `archived` maps to null | [P] section 10 (O-1, O-14) |
| P-8 | Recorded-rejection recovery actions (resubmit, discard local with archive) | [P] section 3 |
Items the report states as already approved policy but that no owner message in this repository records ("[R]" in the S5 doc): payload 224 KiB per operation and 896 KiB per batch, unknown legacy rows never sync, demo rows local-only, dependent operations wait for acknowledgement, tree-delete atomicity deferred to the S3 gate. Treat them as unconfirmed until the owner confirms them.

### 3b. Recommendations (not approvals)
| Topic | Recommendation | Where |
|---|---|---|
| O-1 `completed_at` | Option A (validate only) | wire contract 7 |
| O-6 D-R | Option A, no privilege change | security record 2 |
| O-3 rate limit and retention | throttle per user plus storing only the hash for rejected operations | security record R1, R3 |
| O-5 `request_id` | no server meaning | wire contract 7 |
| S5 backup retention | keep all backups; the owner deletes manually (the report's recommendation; never automatic, OD-8) | S5 doc 16 risk 1 |
| O-11 | keep `blocked_by_conflict` terminal | wire contract 7 item 9 |
| S5 backup method | the earlier recommendation to prefer the online backup API is **withdrawn**: the report's `VACUUM INTO` under lock is acceptable because order is read from the original and the digest covers rowid order | S5 doc 6 |
Recommendations stay here until the owner approves them; only the decision table above records approvals.

## 4. Gates (GO / HOLD / NO-GO)
| Gate | Verdict | Reason |
|---|---|---|
| Hosted S2, S3, S4, throttle, response bound and S9 | **DONE on the TEST project (2026-11-13)** | owner authorization of 2026-11-13; see the acceptance record |
| Further hosted migration of any kind | **HOLD** | no authorization |
| Hosted permission changes | **HOLD** | no authorization; none made |
| Auth activation on the TEST project | **DONE** (owner acceptance 2026-11-14) | public sign-up enabled for development (D-U); production Auth review remains a separate step |
| Synchronization activation for real users / production project | **Not applicable now** (was NO-GO) | no production environment, no real users (policy); the TEST build is for the owner with the existing test account |
| Full SQLite schema v2 and v3 | **GO, done** | local file only; shipped in the DEVELOPMENT TEST build; the migration made a verified backup at the time (not a standing requirement for test data) |
| Merge of the development branch into `main` (Phase 4) | **HOLD** | consolidated Phase 4 PR prepared for owner review; no merge without explicit owner approval (Phase 3 was merged as `9499da6`) |

## 5. Blocker register
| ID | Blocker | Class | State |
|---|---|---|---|
| B-1 | `guard_row` project UPDATE defect | technical | **resolved** (F1 applied to hosted) |
| B-2 | Documentation on `main` described S1 as not applied | documentation | **resolved by this consolidation** once merged to `main` (owner approval to merge is a separate gate) |
| B-3 | Corrected S5 specification text not in the repository | open technical/document | **resolved 2026-11-12**: the Session B report was supplied and is incorporated in `phase-3-s5-outbox-v2.md` |
| B-4 | `completed_at`/`status` rule | owner-approval | **resolved as built** (Option A, O-1) |
| B-5 | Response size bound | owner-approval | **resolved** (response bound S10b applied) |
| B-6 | Rate limit and retention | owner-approval | **partly resolved**: throttle applied; retention/purge deferred to production hardening |
| B-7 | No client revoke RPC; 10-device lifetime cap in practice | owner-approval | **resolved locally** by `nexora_revoke_device` (not hosted) |
| B-8 | S2 end-to-end HTTP path and exposed schemas unverified | owner-approval (hosted gate) | **resolved on the hosted TEST project (2026-11-13), see `docs/operations/hosted-acceptance-record-2026-11-13.md`** |
| B-9 | 8 s statement timeout vs 100-operation call unmeasured | technical, needs hosted | **resolved on the hosted TEST project (2026-11-13), see `docs/operations/hosted-acceptance-record-2026-11-13.md`** |
| B-10 | Direct INSERT/UPDATE on `projects`/`tasks` still granted | owner-approval (S9) | **resolved on the hosted TEST project (2026-11-13), see `docs/operations/hosted-acceptance-record-2026-11-13.md`** |
| B-11 | D-U dashboard audit | owner-approval | **closed for the TEST environment** (D-U decided); production review deferred |
| B-12 | D-S dependency versions and secure storage | owner-approval | **resolved**: no new Dart dependency was added; native DPAPI uses `dart:ffi` |
| B-13 | S5-Q1: representation of preserved v1 `sent`/`failed`/`acked` rows in v2 | owner-approval | **resolved**: class U with verbatim archive (OD-11), implemented and tested |
| B-14 | Windows Flutter checks run only in CI (no Flutter SDK in the agent sandbox) | environment | accepted; CI run recorded in section 7 |
| B-15 | S9, hosted S8 | deferred | **resolved**: hosted S8 acceptance done on the TEST project (2026-11-13) |
| B-20 | PostgREST exposure and real JWT verification for the S2/S3/S4 RPCs | technical | **resolved on the hosted TEST project** (real HTTP/JWT acceptance, acceptance record) |
| B-21 | `NEXORA_SYNC` adapter and engine against Supabase; sign-in code | technical | **resolved**: engine, adapter and sign-in ran against the hosted TEST project in manual Windows acceptance |
| B-22 | Direct INSERT/UPDATE on `projects`/`tasks` is reachable through the Data API (probe: HTTP 201 for the owner's own row) | owner-approval (S9) | **resolved on the hosted TEST project (2026-11-13), see `docs/operations/hosted-acceptance-record-2026-11-13.md`** |
| B-23 | Access tokens are stateless: sign-out ends the refresh token only; an issued access token works until it expires | owner decision | **accepted risk for the TEST environment**; production recommendation: JWT expiry of one hour or less |
| B-24 | The refresh-token reuse window observed in the disposable stack exceeds the configured interval; the hosted setting is unread | owner decision | **accepted risk for the TEST environment**; hosted setting to be reviewed in the production Auth review |
| B-16 | The corrected Session B S5 report was not received on the first reconciliation attempt. | open document | **resolved 2026-11-12**: received as text and incorporated; no line of it is treated as approved beyond the owner directions OD-7 to OD-10 |
| B-17 | Dart `sqlite3` 3.9.1 (the pinned bundle) was not used for the report's checks | open technical | **resolved**: the v2 DDL, triggers, rebuild and backup under lock run as Dart tests on the pinned bundle in Windows CI |
| B-18 | The report's scratch verification was not reproduced in this repository | open technical | **resolved**: reproduced on SQLite 3.53.1 for the DDL and as Dart tests in CI |
| B-19 | The per-operation envelope estimate must be measured against `p_ops::text`; the 8 s timeout against a 100-operation batch is also unmeasured (B-9) | open technical | **partly resolved**: the client computes the exact PostgreSQL `jsonb::text` size and matched the real function byte-for-byte on 40 random batches (local PostgreSQL 16); the hosted 8 s timeout measurement was done (B-9, resolved) |

## 6. Wire contract and architecture references
S2/S5 wire contract: `docs/architecture/s2-wire-contract.md` (authoritative for push). Data contract: `docs/architecture/data-contract.md`. Protocol decisions: `docs/architecture/decisions/0002-sync-protocol.md`. S5: `docs/coordination/phase-3-s5-outbox-v2.md`.

## 7. Evidence index (every implemented item)
| Item | Evidence |
|---|---|
| Phase 2B apply | `docs/operations/phase-2b-apply-record.md`; suite `supabase/tests/rls_and_contract_test.sql` (57) |
| F1 | `docs/operations/f1-hosted-fix-record.md`; `supabase/tests/fix_projects_update_guard_test.sql` (29) |
| S1 | `docs/operations/s1-hosted-deployment-record.md`; `s1_sync_schema_test.sql` (43) |
| S2 | `s2_auth_grants_test.sql` (27), `s2_device_test.sql` (23), `s2_apply_test.sql` (89), `s2_push_test.sql` (49), `s2_contract_test.sql` (47), `s2_security_direct_test.sql` (41); concurrency scripts; `mutation_checks.sh` (21 mutations); workflow `.github/workflows/supabase-tests.yml` |
| S5-0 | `test/features/tasks/data/migration_v1_golden_test.dart`, `outbox_failure_injection_test.dart`, `test/fixtures/v1/` (PROVENANCE.md), workflow `.github/workflows/ci.yml` |
| S5 | `lib/features/tasks/data/{schema_v2,migration_v2,outbox_store,entity_patch,snapshot_digest,jsonb_size}.dart`; tests `migration_v2_test.dart`, `outbox_store_test.dart`, `outbox_property_test.dart`, `jsonb_size_test.dart`, support `test/support/v1_database.dart`; record `docs/operations/s5-implementation-record.md` |
| S3, S4 | `s3_resolve_test.sql` (68), `s3_tree_delete_test.sql` (39), `s3_revoke_test.sql` (28), `s4_pull_test.sql` (111), `concurrency/s3_s4_concurrency.sh`, `mutation_checks.sh` (37 mutations), `verify_rollbacks.sh`; record `docs/operations/s3-s4-implementation-record.md`; PostgreSQL 17 run on `f7e742e`: 43296292663 (success) |
| S6 | `lib/features/sync/`, `lib/features/tasks/data/{pull_applier,sync_state_store,schema_v3,server_row}.dart`, `test/features/sync/sync_engine_test.dart`, `test/support/fake_sync_server.dart`; record `docs/operations/s6-implementation-record.md`; Windows CI run 43306627424 on `b90840d` (success, 447 tests) |
| Two-device end-to-end (PostgreSQL 17) | `test/e2e/`, workflow `.github/workflows/e2e-sync.yml`; 15 scenarios, run 43299291266 on `0c1f84e` (success) |
| S7, S8 | `lib/features/auth/`, `lib/runtime/`, `lib/app/{account_panel,sync_panel}.dart`; tests `test/features/auth/`, `test/runtime/`, `test/s8/windows_acceptance_test.dart`, `test/http/` (21 tests, workflow `.github/workflows/http-integration.yml`); record `docs/operations/s7-s8-implementation-record.md`; code head `959558a`: Windows `CI` run 43323362456 (success, 515 tests passed, 35 skipped: 14 `e2e` + 21 `http`, all classified in the S7/S8 record), `http-integration` run 43322576202 (21/21), `e2e-sync` run 43322576250 (14/14); run ids of the exact final head are in the final report |
| Documentation consistency (links, paths, migration list, stale phrases, policy rules OD-7 to OD-9, self-test) | `tools/check_docs.py`, workflow `.github/workflows/docs-check.yml` |
| Hosted deployment and acceptance (S2 to S9) | `docs/operations/hosted-acceptance-record-2026-11-13.md`, `docs/operations/hosted-readonly-preflight-2026-11-12.md`, `docs/operations/combined-hosted-acceptance-operation.md`, `tool/hosted_acceptance.py` |
| Hardening (throttle, response bound, S9) | `docs/operations/hardening-implementation-record.md` |
| Sign-in hang fix | `docs/operations/windows-signin-hang-fix-record-2026-11-13.md` |
| Conflict resolution UI | `docs/operations/conflict-resolution-ui-record-2026-11-13.md` |
| Release candidate | `docs/operations/release-candidate-guide.md`, `docs/operations/release-acceptance-checklist.md`, `docs/operations/v1-rc-evidence-record.md` |
| Phase 3 final CI (development head `f5e0665`) | Windows `CI` 43437771188; PostgreSQL 17 `supabase-tests` 43430011558; `http-integration` 43429978322; `e2e-sync` 43429978475; `docs-check` 43429978295; sync-enabled DEVELOPMENT TEST build 43429978333 (artifact 14039172511, built from `de8f326`, the last code change). Documentation-only commits after that head are verified by the runs listed in the integration report. |
| Manual Windows acceptance | owner statement 2026-11-14 (items listed in section 1); no screenshots or logs are stored in the repository |
| Phase 4 reminders, tray, notifications | `docs/operations/phase-4-implementation-record-2026-11-14.md`; tests `test/features/reminders/`, `test/platform/`, `test/app/reminder_ui_test.dart`, `test/runtime/reminder_runtime_test.dart`; native `windows/runner/desktop_integration.{h,cpp}`; `tool/windows_shell_smoke.ps1` |
| Phase 4 CI (development head `914435c`, code head; later commits are documentation only) | Windows `CI` 43620789345; sync-enabled DEVELOPMENT TEST build 43621629032 (artifact `nexora-windows-sync-DEVELOPMENT-TEST`); PostgreSQL 17 `supabase-tests` 43621631547; `http-integration` 43621634472; `e2e-sync` 43621637048; `docs-check` 43621640442. The run ids for the final documentation head are in the integration report. |
| Manual Windows acceptance, Phase 4 | owner statement 2026-11-14 (six checks listed in section 1); no screenshots or logs are stored in the repository |
| Phase 5 | `docs/operations/phase-5-implementation-record-2026-11-16.md`; tests `test/app/phase5_ui_test.dart`, `test/app/sync_presentation_test.dart`, `test/features/tasks/application/{task_workspace_phase5,visibility_regression}_test.dart`, `test/features/tasks/data/workspace_delete_sqlite_test.dart`, goldens `test/golden/phase5_golden_test.dart`; CI run ids are in the pull request |

## 8. Contradictions that cannot be resolved from approved decisions
1. ~~The corrected S5 specification text was missing~~ (B-3, B-16): supplied and incorporated 2026-11-12.
2. CR-2A-001 proposed `ORDER BY created_at_utc, rowid`, mapping `sent` to `pending` (automatic replay) and copying `failed` unchanged. **Resolved by owner direction:** rowid order (OD-7), no automatic replay or loss (OD-9); the proposal SQL is corrected and withdrawn as a mapping. The v2 representation of preserved rows stays open (B-13).
3. The plan (S3) lists `create_under_tombstoned_parent_conflicts`; the owner direction (OD-4) makes it `parent_invalid`. Resolved in favor of OD-4; the plan line is annotated.
4. Plan 4.3, CR-2A-001 section 2 and data-contract row 3 said the engine re-bases the next operation from the previous acknowledgement; the report shows that can suppress a real conflict. **Resolved by annotation**: those lines are marked superseded by rule R (proposal P-1, pending approval); the checker flags unannotated copies.
5. Plan 4.3 and CR REQ-6 send tombstone chains leaf-first as if atomic; S2 applies each operation in its own sub-transaction. **Held until the S3 gate** (annotated); the local precheck is proposal O-13.
6. The earlier recommendation to prefer the online backup API contradicts the report's verified `VACUUM INTO` under lock. **Resolved**: the recommendation is withdrawn (section 3b), conditional on a digest that includes rowid order.
7. The report asks for two S2 wire additions (`version_before`, conflict detail) as if missing; both already exist in this branch (OD-6, implemented locally, not hosted). The report read an older snapshot (`a263f8a`); nothing further is needed beyond the open question O-11.


## 9. Remaining V1 work
| Item | State |
|---|---|
| Phase 5: UI/UX modernization | implemented on `feature/phase-5-ui-ux`; waiting for the owner's Windows acceptance (`docs/operations/phase-5-acceptance.md`) and the merge decision |
| Installer, signing, release packaging decision | not started; scope to be set by the owner |
| Production hardening (Auth review, JWT expiry, log retention/purge, sign-up policy) | out of scope: no production exists (`development-environment-policy.md`); revisit only if the owner starts a production phase |
| Synchronized reminders | not planned for V1 (D-RM); would need a hosted schema change, prepared locally and deployed only with separate authorization |
| Test environment data (test@test.com, nx-accept-a/b@example.test, about 1,022 test tasks) | kept; must not be deleted without owner instruction |
| Merge of Phase 4 into `main` | done (PR #18) |
| Merge of Phase 5 into `main` | awaiting the owner's acceptance and approval of the Draft PR |
