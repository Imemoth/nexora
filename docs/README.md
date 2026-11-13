# Nexora documentation map

**Status of the project, slices, migrations, owner decisions, gates and blockers: `docs/coordination/status-register.md` (single source of truth).** Everything else is design, evidence or history and links there. Rule: a document may describe its own subject in detail, but must not restate current phase or deployment status except by linking the register. `tools/check_docs.py` (CI: `docs-check.yml`) checks links, referenced paths and banned stale phrases.

## Authority order for the synchronization protocol
1. Owner decisions: `architecture/decisions/0002-sync-protocol.md` and the decision register in the status register.
2. S0 data contract: `architecture/data-contract.md`.
3. S2 wire contract (push, register): `architecture/s2-wire-contract.md`; S3/S4 wire contract (tree delete, resolve, revoke, pull): `architecture/s3-s4-wire-contract.md`.
4. S5 planning document: `coordination/phase-3-s5-outbox-v2.md` (reconstruction, see its provenance note).
5. Plans (`superpowers/plans/`): intent at the time of writing; where they differ from 1-4 the higher item wins.

## Inventory
| Path | Kind | Current / historical | Notes |
|---|---|---|---|
| `coordination/status-register.md` | register | **current, authoritative** | status, migrations, decisions, gates, blockers, evidence index |
| `coordination/phase-3-s5-outbox-v2.md` | spec (reconstructed, corrected for OD-7 to OD-9) | current planning baseline | S5 not implemented; Session B report not yet received (B-16) |
| `coordination/phase-2a-sync-requirements.md` | change request CR-2A-001 | current (requirements REQ-1..8); answered in part | proposal SQL corrected 2026-11-12 (rowid order, no auto replay); see S5 doc 3a |
| `architecture/data-contract.md` | contract | current | status column kept in step with the register |
| `architecture/s2-wire-contract.md` | contract | current, authoritative for push | amended 2026-11-12 |
| `architecture/s3-s4-wire-contract.md` | contract | current, authoritative for tree delete, resolve, revoke and pull | |
| `architecture/sync-contract.md` | contract | current (S0 protocol detail) | |
| `architecture/sync-design-phase-2b.md` | design | historical design (Phase 2B), still valid for rationale | |
| `architecture/phase-2a-data-contract-alignment.md` | alignment record | historical (written on the Phase 2A branch) | hosted status line corrected |
| `architecture/decisions/0001-flutter-offline-first.md` | ADR | current | |
| `architecture/decisions/0002-sync-protocol.md` | ADR | current | implementation-status table corrected |
| `operations/phase-1-acceptance.md` | acceptance | historical record | |
| `operations/phase-2a-windows-acceptance.md` | acceptance | historical record (owner pass) | |
| `operations/phase-2b-apply-record.md` | apply record | historical record | |
| `operations/f1-hosted-fix-record.md` | apply record | historical record | |
| `operations/s1-hosted-deployment-gate.md` | gate report | **superseded** by the record below | kept for history |
| `operations/s1-hosted-deployment-record.md` | apply record | historical record | |
| `operations/s2-implementation-record.md` | implementation record | current evidence for S2 | |
| `operations/security-review-s1.md` | review | historical | |
| `operations/security-hardening-decision-record.md` | decision record | current | S2 privileges and abuse resistance |
| `operations/s5-migration-safety-test-spec.md` | test spec | current | M-tests mapped to implemented tests |
| `operations/s5-implementation-record.md` | implementation record | current evidence for S5 | what was built, evidence, deviations, open integration points |
| `operations/s3-s4-implementation-record.md` | implementation record | current evidence for S3 and S4 | RPC privilege inventory, suites, decisions |
| `operations/s6-implementation-record.md` | implementation record | current evidence for S6 and the two-device end-to-end suite | components, data-preservation rules, limitations |
| `operations/s7-s8-implementation-record.md` | implementation record | current evidence for S7, S8, the HTTP/JWT environment and findings | auth, per-account storage, real transport wiring, acceptance suite, limitations |
| `operations/hosted-deployment-checklist-s2-s4.md` | checklist (prepared, not executed) | current | exact migration order, rollback, Data API exposure, hosted HTTP/JWT acceptance, 8 s timeout measurement, activation and rollback |
| `operations/rate-limit-and-log-retention-recommendations.md` | recommendations (O-3) | current | none implemented |
| `operations/s9-direct-grants-removal-plan.md` | plan (not authorized) | current | removal of direct table-write grants (B-10) |
| `operations/hardening-implementation-record.md` | implementation record | current evidence for the throttle, response bound and S9 | limits, mutation and rollback evidence |
| `operations/combined-hosted-acceptance-operation.md` | runbook (prepared, not executed) | current | ordered operation, digests, verification queries, stop-on-failure, kill switch, execution record template |
| `operations/hosted-readonly-preflight-2026-11-12.md` | preflight record | current | read-only hosted state, no writes |
| `operations/release-candidate-guide.md` | user guide | current | install, first run, sign-in, import, backup and recovery |
| `operations/release-acceptance-checklist.md` | checklist | current | V1 release acceptance with evidence lines |
| `operations/remaining-blocker-register.md` | register | current | owner decisions that block the next step |
| `operations/auth-dashboard-audit.md` | audit | open (D-U) | |
| `operations/supabase-access.md` | operations note | current | |
| `operations/supabase-sql-location.md` | operations note | current (where the SQL lives) | |
| `operations/branching-policy.md` | operations note | current | |
| `superpowers/specs/2026-11-11-nexora-v1-design.md` | product spec | current | |
| `superpowers/plans/*` | plans | historical intent (see authority order) | status lines point to the register |
