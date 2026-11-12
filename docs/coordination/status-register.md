# Nexora status register (single source of truth)

Last consolidated: 2026-11-12, branch `claude/affectionate-turing-unzmd2`. **This file is the only place that states current phase and slice status, migration history, owner decisions with their approval status, gates and blockers.** Other documents describe design or evidence and link here; where another document disagrees with this register, this register is correct unless it cites that document as the exception. The documentation map is `docs/README.md`.

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
| S2 push RPC | **Implemented locally and tested (PostgreSQL 16 locally, PostgreSQL 17 CI). NOT applied to hosted, not exposed.** Locally tested baseline only; not hosted-ready (section 4) | `docs/operations/s2-implementation-record.md`, `docs/architecture/s2-wire-contract.md`, `docs/operations/security-hardening-decision-record.md` |
| S3 resolve and delete refinements | Not started (deferred) | plan section 6 |
| S4 pull and cursor | Not started (deferred) | plan section 6 |
| S5 SQLite outbox v2 | **Specified, not implemented; no SQLite schema v2.** S5-0 safety net (golden v1 tests, fixtures, failure injection) implemented | `docs/coordination/phase-3-s5-outbox-v2.md`, `docs/operations/s5-migration-safety-test-spec.md`, `test/features/tasks/data/` |
| S6 sync engine, S7 auth/session, S8 end-to-end, S9 activation | Not started (deferred) | plan section 6 |
| Synchronization and Auth activation | **Disabled** (flag OFF, D-F). No auth activation, no sync traffic, hosted tables empty | all gates in section 4 |

## 2. Migration history
| Repo file | Hosted version | State |
|---|---|---|
| (initial schema; applied through the Supabase connector, not stored in the repo; reproduced by `supabase/tests/00_bootstrap_local.sql` for local tests) | `20261112111349` `nexora_initial_domain_schema` | applied |
| `supabase/migrations/20261112115809_nexora_security_hardening.sql` | `20261112115809` | applied |
| `supabase/migrations/20261112120132_nexora_contract_alignment.sql` | `20261112120132` | applied |
| `supabase/migrations/20261112120149_nexora_sync_foundation.sql` | `20261112120149` | applied |
| `supabase/migrations/20261112125000_nexora_fix_projects_update_guard.sql` (F1) | `20261112142732` | applied (hosted timestamp differs from the file name) |
| `supabase/migrations/20261112130000_nexora_sync_protocol_schema.sql` (S1) | `20261112151851` | applied; SHA-256 `cb947073...5d42e2`, rollback `97f5e738...8596` |
| `supabase/migrations/20261112160000_nexora_sync_push.sql` (S2) | none | **not applied**; rollback `supabase/rollback/20261112160000_rollback_s2_sync_push.sql` |
Hosted history read read-only on 2026-11-12: exactly the first six rows above. Local migration files may be edited while unapplied (the S2 file was amended on 2026-11-12 for `version_before` and `conflict`); applied files are frozen.

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
| D-R | INVOKER wrappers over private DEFINER functions | conditional | exact grants, `search_path`, ownership, non-exposure: **met locally**; hosted HTTP verification is part of the S2 gate; Option A (no change) awaits confirmation (security record) |
| D-O | sort_order server-wins, auditable | conditional | **met in S1/S2** (DB-enforced audit; tests) |
| D-S | Client dependency architecture | approved in principle | exact versions and secure storage need review before S7 |
| D-U | Anonymous sign-in and public sign-up | unverified | dashboard audit before auth activation (`docs/operations/auth-dashboard-audit.md`) |
| A-S1 | S0 and S1 on the dev branch; later hosted S1 apply | approved | owner messages "Phase 3 Owner Architecture Decision" and "S1 Hosted Deployment"; recorded in the S1 record |
| A-F1 | Standalone F1 hosted fix only | approved, done | f1 record |
| A-S2 | Implement S2 locally; no hosted S2 | approved, done locally | S2 record |
| OD-1 | S2 accepted as locally tested baseline, **not** hosted-ready | approved (direction 2026-11-12) | consolidation message |
| OD-2 | Corrected S5 specification is the planning baseline, subject to compatibility and migration-safety gates | approved (direction 2026-11-12); **the text is missing from the repository** (blocker B-3) | consolidation message |
| OD-3 | sort_order mixed-field update: server wins for `sort_order` only, other fields apply | **approved** (owner direction 2026-11-12, item 4) | wire contract 7 |
| OD-4 | Creation under a tombstoned parent is `rejected: parent_invalid` | **approved** (owner direction 2026-11-12, item 5) | wire contract 7; supersedes the plan's S3 `create_under_tombstoned_parent_conflicts` |
| OD-5 | Rejected operations are immutable history; recovery uses a new operation id | **approved** (owner direction 2026-11-12, item 3) | wire contract 2 |
| OD-6 | `version_before` in applied results; conflict detail for the S5 mirror | **approved** (owner direction 2026-11-12, items 1-2) | wire contract 2 |
| O-1 | `completed_at`/`status` rule | open | recommendation: Option A (validate only); prototype in `supabase/proposed/`; Option B conflicts with S0 |
| O-2 | Response size bound (D-RESP) | open | wire contract 3.2 |
| O-3 | Rate limiting and log retention/purge path | open | security record R1-R3 |
| O-4 | Client device revoke RPC | open | security record R6 |
| O-5 | `request_id` server meaning | open | recommendation: none; client-side only |
| O-6 | D-R Option A confirmation (no privilege change) | open | security record section 2 |
| O-7 | S5 open points S5-Q1 to S5-Q6 (failed-state mapping, stored version of pending create, title limit, owner binding name, `request_id`, synced flag) | open | S5 document section 7 |
| O-8 | Scope and order of S3 and S4 | open | plan section 6 |
| O-9 | Hosted S2 gate approval | open | S2 record gate steps 1-5 |
| O-10 | Backup retention for the local SQLite file before migration 2 | open | S5 safety spec section 2 |

## 4. Gates (GO / HOLD / NO-GO)
| Gate | Verdict | Reason |
|---|---|---|
| Hosted S2 deployment | **NO-GO** | owner approval O-9 absent; HTTP/JWT end-to-end, exposed-schemas check and 8 s timeout behavior unproven; O-1, O-2, O-3 undecided |
| Further hosted migration of any kind | **HOLD** | no authorization |
| Hosted permission changes | **HOLD** | no authorization; none made |
| Auth activation | **NO-GO** | D-U unaudited; S7 not started |
| Synchronization activation | **NO-GO** | S3, S4, S5, S6, S7, S8, S9 not done |
| Full SQLite schema v2 (S5 implementation) | **HOLD** | needs S5 specification reconciliation (B-3), S5-Q1 and owner start approval |
| Local development of S2/S5-0 and docs on the existing branch | GO | authorized |

## 5. Blocker register
| ID | Blocker | Class | State |
|---|---|---|---|
| B-1 | `guard_row` project UPDATE defect | technical | **resolved** (F1 applied to hosted) |
| B-2 | Documentation on `main` described S1 as not applied | documentation | **resolved by this consolidation** once merged to `main` (owner approval to merge is a separate gate) |
| B-3 | Corrected S5 specification text not in the repository | open technical/document | **open**: supply the text; `phase-3-s5-outbox-v2.md` is a reconstruction |
| B-4 | `completed_at`/`status` rule | owner-approval | open (O-1) |
| B-5 | Response size bound | owner-approval | open (O-2) |
| B-6 | Rate limit and retention | owner-approval | open (O-3) |
| B-7 | No client revoke RPC; 10-device lifetime cap in practice | owner-approval | open (O-4) |
| B-8 | S2 end-to-end HTTP path and exposed schemas unverified | owner-approval (hosted gate) | open (O-9) |
| B-9 | 8 s statement timeout vs 100-operation call unmeasured | technical, needs hosted | open |
| B-10 | Direct INSERT/UPDATE on `projects`/`tasks` still granted | owner-approval (S9) | open by design |
| B-11 | D-U dashboard audit | owner-approval | open |
| B-12 | D-S dependency versions and secure storage | owner-approval | open until S7 |
| B-13 | S5-Q1: v1 `failed` outbox state has no v2 mapping (defect in the CR-2A-001 proposal) | open technical | open |
| B-14 | Windows Flutter checks run only in CI (no Flutter SDK in the agent sandbox) | environment | accepted; CI run recorded in section 7 |
| B-15 | S3, S4, S6, S7, S8, S9 | deferred | not started |

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
| Documentation consistency | `tools/check_docs.py`, workflow `.github/workflows/docs-check.yml` |
Run results for the current head are recorded in the final report of this consolidation and in `docs/operations/s2-implementation-record.md` section "Consolidation validation".

## 8. Contradictions that cannot be resolved from approved decisions
1. The consolidation message says the S5 specification is a "corrected" baseline; no such text exists in the repository (B-3). Not resolvable without the text.
2. CR-2A-001 proposes mapping v1 `failed` outbox rows unchanged although v2 has no `failed` state (B-13). A mapping is a new policy; not chosen here.
3. The plan (S3) lists `create_under_tombstoned_parent_conflicts`; the owner direction (OD-4) makes it `parent_invalid`. Resolved in favor of OD-4; the plan line is annotated.
