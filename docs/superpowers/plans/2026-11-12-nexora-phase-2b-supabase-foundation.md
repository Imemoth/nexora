# Nexora Phase 2B Supabase Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use `- [ ]`.

**Goal:** Apply a reviewed, additive schema increment (security hardening, contract alignment, inert sync tables) to project `uicccaawtjvqggeufbez`.
**Architecture:** Three versioned SQL migrations, verified on a disposable Postgres with an RLS/contract test suite, then applied by a connector with write access. Sync stays disabled.
**Tech Stack:** PostgreSQL 17 (Supabase), psql, Supabase MCP.
**Spec:** `docs/superpowers/specs/2026-11-11-nexora-v1-design.md`, `docs/architecture/data-contract.md`, `docs/architecture/sync-design-phase-2b.md`.

## Global Constraints
- No service-role key in client or repo. No production sync. No destructive migration. Owner approval before any hosted apply by a non-owner-authorized path.

## Review Focus
- Owner decision: `owner_id`/`version` vs spec `workspace_id`/`revision`.
- Dart enum mapping (`review`, `archived`, `none`) must be mirrored by the SQLite implementation.
- Pull cursor gaps from concurrent transactions.
- Hard-delete removal: clients must use tombstones.
- Tests ran on PG 16 locally; hosted is 17.

### Task 1: Local verification — DONE
- [x] Bootstrap fixture + 3 migrations + `supabase/tests/rls_and_contract_test.sql` → 57 assertions pass; same suite fails on the pre-migration schema (negative control).

### Task 2: Apply to hosted (BLOCKED: needs write-capable connector)
- [ ] Re-run read-only checks (project id, migration list = 1, row counts = 0).
- [ ] Apply the three files in order, names `nexora_security_hardening`, `nexora_contract_alignment`, `nexora_sync_foundation`.
- [ ] Run `rls_and_contract_test.sql` wrapped so it rolls back (it already ends in `rollback`); expect `passed = 57`.
- [ ] `get_advisors(security)` expect no `rls_auto_enable` findings.

### Task 3: SQLite parity (parallel owner)
- [ ] Adopt the wire values and `version`/`deleted_at`/`change_seq` columns from the contract; do not modify from this branch.
