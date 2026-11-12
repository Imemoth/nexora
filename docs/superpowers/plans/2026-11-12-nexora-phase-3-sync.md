# Nexora Phase 3 Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status: APPROVED by the owner on 2026-11-12 (see `docs/architecture/decisions/0002-sync-protocol.md` for conditions). S0 and S1 are authorized; S1 is implemented on the dev branch, passes PostgreSQL 17 CI (runs 43217510081, 43219771092, 43225149883, 43236184204) and is NOT applied to the hosted project. The standalone `guard_row` fix (`20261112125000`) was applied to hosted on 2026-11-12 as `20261112142732` (`docs/operations/f1-hosted-fix-record.md`). S2 onward needs separate approval.** No hosted change, no user or data creation, no sharing, no merge, no deploy.

**Goal:** Two or more devices of one user converge on the same projects and tasks through Supabase, with no lost edit, no duplicate application and no cross-user access.

**Architecture:** The client keeps SQLite as the UI source of truth and a transactional outbox. A small RPC protocol (register, push, pull, resolve) runs server-side in one transaction per operation, keyed by `(user_id, operation_id)`. Concurrency is detected per field from a server-owned `base_version`. Pull is a monotonic per-user cursor made safe by serializing each user's writers.

**Tech Stack:** PostgreSQL 17 (Supabase), PL/pgSQL RPCs, SQLite (`sqlite3` package per Phase 2A D1), Dart sync engine in `lib/features/sync/`, Supabase Auth.

**Spec:** `docs/superpowers/specs/2026-11-11-nexora-v1-design.md`, `docs/architecture/data-contract.md`, `docs/architecture/sync-design-phase-2b.md`, `docs/architecture/sync-contract.md`, `docs/operations/phase-2b-apply-record.md`. Phase 2A: branch `origin/feature/phase-2a-sqlite` (plan + `lib/features/tasks/data/migrations.dart`, read only).

## Global Constraints
- Owner model is `owner_id` and `version` (D1 approved). No workspaces, no sharing; `project_members` stays inert.
- Wire values: status `open|in_progress|review|done|archived`; priority `none|low|medium|high`; title 1–200; `notes` non-null `''`; dates `YYYY-MM-DD`; UTC `timestamptz`.
- Server owns `version`, `created_at`, `updated_at`, `change_seq`, tombstone time. Device clocks never order anything.
- No service-role key in client, CI or repo. Client uses the publishable key plus the user JWT.
- Synchronization is behind a feature flag that defaults to OFF until the owner approves activation (SG12).
- Hosted tests are rollback-only and create no persistent users or data. Concurrency tests run on disposable PostgreSQL 17.
- No new dependency without owner approval (D-S below). No change to the Phase 2A branch from this plan.

## Review Focus
- A retry after a lost response must not apply twice (crash after server commit, before client ack).
- A pull must not skip a row committed late by a concurrent writer.
- Deleting a parent while another device adds or edits a child must not silently delete that child.
- User B signing in on a device that holds user A's unsynced data must not push A's data into B's account.
- A client that writes tables directly (bypassing the RPC) must not be able to overwrite without conflict detection.

---

## 1. Verified baseline (read-only)
| Fact | Evidence |
|---|---|
| Hosted schema has versioning, tombstones, `change_seq`, guard triggers, inert `devices`, `sync_operations`, `sync_conflicts` | `docs/operations/phase-2b-apply-record.md`; hosted regression 57/57 |
| `authenticated` still has INSERT/UPDATE on `projects` and `tasks` (needed pre-sync) | migration `20261112115809` |
| No RPC exists; sync tables have no client write grants | migration `20261112120149` |
| Phase 2A outbox has `upsert`/`delete`, `base_version >= 0`, states `pending/sent/acked/failed`, no device id, no cursor, no conflict table, no ordering column | `migrations.dart` on `feature/phase-2a-sqlite` |
| Phase 2A plan §2 predates 2B: it still says the server rejects `review`, `archived`, `none` and has nullable notes. All four are now resolved server-side | contract vs 2A §2.1 |
| Phase 2A plans a local `+1 per committed update` version. That conflicts with server-owned versions (see §4.1) | 2A §2.1 |
| Update (2026-11-12): at `c970d61` (PR #13, Draft) Phase 2A implements REQ-1 (no local version bump), REQ-7 and REQ-8 and the transaction half of REQ-5. Not implemented: outbox v2, `sync_state`, conflict mirror, leaf-first tombstones, patch-only payloads | `phase-2a-data-contract-alignment.md` on `feature/phase-2a-sqlite` |

## 2. Protocol
All RPCs are called by `authenticated` only. The user is always `auth.uid()`; a null or anonymous JWT is rejected. Nothing user-supplied names an owner.

```
public.nexora_register_device(p_device_id uuid, p_label text) returns jsonb
public.nexora_sync_push(p_device_id uuid, p_ops jsonb)        returns jsonb  -- {results:[Result]}
public.nexora_sync_pull(p_device_id uuid, p_cursor bigint, p_limit int default 200) returns jsonb
   -- {changes:[{entity_type,row}], conflicts:[Conflict], next_cursor, has_more}
public.nexora_resolve_conflict(p_device_id uuid, p_operation_id uuid, p_conflict_id uuid,
                               p_resolution text, p_values jsonb) returns jsonb
```
Op: `{operation_id, entity_type: project|task, entity_id, op_type: create|update|delete, base_version, patch, client_created_at}`.
Result: `{operation_id, status: applied|conflict|rejected, applied_version, row, conflict_id, error_code, replayed}`.

**Exposure pattern (decision D-R):** `public.*` wrappers are SECURITY INVOKER and call `nexora_private.*` SECURITY DEFINER functions (`search_path=''`). `nexora_private` is not exposed through the Data API. This keeps the Security Advisor at zero findings and still lets the private function write the sync tables.

## 3. Server algorithm (one transaction per operation)
1. `pg_advisory_xact_lock(hashtextextended(user_id::text, 0))`: serializes all of one user's writers.
2. Validate device: exists for this user, `revoked_at is null`. Otherwise `rejected: device_invalid` (same message for unknown and foreign devices).
3. Validate op shape: whitelist per entity (project: `name, description, color, is_archived, sort_order`; task: `parent_id, title, notes, status, priority, due_date, completed_at, sort_order`; create adds `project_id`). Unknown keys, `owner_id`, `user_id`, `version` → `rejected: invalid_patch`. Size limits: ≤100 ops/push, patch ≤256 KB.
4. Idempotency gate: `insert into sync_operations … on conflict (user_id, operation_id) do nothing`. If the row already exists: same `request_hash` returns the stored `result` with `replayed=true`; a different hash is `rejected: operation_id_reuse`. A concurrent duplicate blocks on the unique index until the first commits.
5. Load the entity `for update` where `owner_id = user_id`. Not found and foreign are indistinguishable (`not_found`).
6. Concurrency rule (field level): the row keeps `field_versions jsonb` (field → version when last changed; new column, §6 S1). An `update` conflicts only if some patch field has `field_versions[f] > base_version` and the current value differs from the patch value. Equal values are a no-op merge. Different fields merge without conflict.
7. Result: apply (guard trigger bumps `version`, assigns `change_seq`), or write one `sync_conflicts` row holding `server_value`, `client_value`, `fields`, `base_version`, `server_version`, `kind`. A conflicting op applies nothing (atomic per op). Store `result` on the operation row, commit.
8. A later op for an entity with an open conflict from the same user returns `rejected: blocked_by_conflict`.
9. Each op runs in its own sub-transaction (`begin … exception … end` block) so one failure does not abort the batch. A server error is a `rejected` result with a stable `error_code`; transient database errors are surfaced as HTTP errors so the client retries the whole batch (safe: idempotent).

**Conflict kinds:** `field` (same-field concurrent edit), `edit_deleted` (update on tombstone), `delete_edited` (delete whose base is older than a later edit), `parent_deleted` (create or move under a tombstoned parent), `parent_has_live_children` (delete of a parent with live children), `cycle`, `exists` (create with an existing id and different content).

**Resolution** (`nexora_resolve_conflict`, itself idempotent by `p_operation_id`): `resolved_server` (discard the client patch), `resolved_client` (re-apply the stored client patch at the current version), `resolved_merged` (apply `p_values` at the current version). `edit_deleted` allows only `resolved_server` or "recreate as a new entity" (client-side copy with a new id; tombstones are irreversible in V1). Both values stay in the conflict row after resolution.

## 4. Client design

### 4.1 Local data semantics (to coordinate with Phase 2A)
- Local `version` means "last server version known", changed only by pull or by an ack. A local edit does not bump it. `base_version` of an op is that stored value.
- Local dirty fields are derived from pending outbox ops. A pull never overwrites a field that has a pending op; the server row is stored and the field conflict is detected at push time.
- The domain change and its outbox row are written in one SQLite transaction (already planned in 2A §5.4). A failure leaves neither.
- An entity with an unacknowledged create has all its operations at `base_version = 0`; the engine re-bases each from the create's ack. Update operations carry only changed fields.

### 4.2 Outbox v2 (proposed forward migration; owner of 2A decides)
`sync_outbox`: add `seq INTEGER PRIMARY KEY AUTOINCREMENT` (strict send order), map `upsert` to server `create|update` by `base_version = 0`, states `pending → in_flight → applied | conflict | rejected` (crash recovery returns `in_flight` to `pending`), `request_id`, `sent_at`, `server_result_json`. New tables: `sync_state(singleton: user_id, device_id, cursor, state)`, `sync_conflicts_local` (mirror). `meta.user_id` binds the database to one user.

### 4.3 Engine behaviour
- One in-flight op per entity, in `seq` order. Before sending a follow-up op for an entity, its `base_version` is rewritten from the previous ack.
- After a non-applied result for an entity, later ops of that entity are held until the conflict is resolved.
- Delete of a task or project with descendants sends tombstone ops leaf-first in one push, then the parent. A parent delete is never cascaded by the server (decision D-P).
- Retry: exponential backoff with jitter, capped; transient errors keep the op `pending`; terminal `rejected` surfaces to the user and is never dropped silently.
- Triggers: app start, after a local commit, 60 s timer while foreground, manual. No background sync, no Realtime (V1 non-goal).
- Pull applies each page in one SQLite transaction with `defer_foreign_keys` and advances `cursor` in the same transaction. After `has_more=false` an orphan check runs; any orphan triggers a full re-pull.
- Auth: a 401 pauses sync, keeps ops queued, refreshes the session. A user change on the device is refused until the old user's queue is empty or exported.

## 5. Pull correctness
`change_seq` is assigned inside the writer's transaction but commits in a different order, which is the classic skipped-row race. Because (a) all sync writes take the per-user advisory lock before allocating `change_seq`, (b) the lock is held until commit and (c) direct writes to `projects`/`tasks` are revoked at activation (SG5), the committed `change_seq` values of one user form a commit-ordered sequence. `pull` is `where owner_id = auth.uid() and change_seq > cursor order by change_seq limit N`; no committed row can appear below an already returned cursor. Tests prove this with an uncommitted competing transaction (§7). If the owner prefers not to rely on lock discipline, the fallback is a `change_txid xid8` fence (`change_txid < pg_snapshot_xmin(pg_current_snapshot())`), at the price of delayed visibility behind long open transactions.

## 6. Implementation slices (each independently reviewable and revertible)

### S0 Contract freeze and Phase 2A coordination (docs only)
- [ ] Owner approves the decisions in §8. Update `docs/architecture/data-contract.md` with: server-owned local `version`, op type mapping, `field_versions`, conflict kinds, the no-cascade delete rule.
- [ ] Send the §4 items to the Phase 2A owner as a written change request. Do not edit their branch.

### S1 Server schema increment (new migration `…_nexora_sync_protocol_schema`) — IMPLEMENTED LOCALLY, NOT APPLIED
Actual scope (supersedes the list below where they differ): `field_versions` on both tables; guard trigger takes the per-user advisory lock before `change_seq` (D-L) and is `ENABLE ALWAYS`; conflict `kind` plus auditable resolution columns, append-only `sync_operations`, immutable conflict values (D-O); device cap (D-D); FK cascade fix; FK indexes; fix for the Phase 2B project-update defect. Tests: `supabase/tests/s1_sync_schema_test.sql`, `supabase/tests/concurrency/lock_discipline.sh`.
**Files:** Create `supabase/migrations/<ts>_nexora_sync_protocol_schema.sql`; Test `supabase/tests/sync_schema_test.sql`.
**Interfaces — Produces:** `projects.field_versions jsonb`, `tasks.field_versions jsonb` maintained by `nexora_private.guard_row`; `sync_conflicts.kind text` (enum check above) and `resolution_operation_id uuid`; `devices.last_push_at`; unique cap of 10 active devices per user.
- [ ] Write failing tests: `field_versions` updates only for changed fields; unchanged fields keep their version; forged `field_versions` ignored; kind check rejects unknown values.
- [ ] Implement; run on local PG17; run the existing 57 assertions (must stay green).

### S2 Server push: register, create, update, idempotency
**Files:** Create `supabase/migrations/<ts>_nexora_sync_push.sql`; Test `supabase/tests/sync_push_test.sql`.
**Interfaces — Produces:** `nexora_register_device`, `nexora_sync_push` (create/update only), `nexora_private.apply_operation(p_user uuid, p_device uuid, p_op jsonb) returns jsonb`.
- [ ] Failing tests: `replay_returns_stored_result_and_version_once`, `same_operation_id_other_hash_rejected`, `other_user_same_operation_id_independent`, `foreign_device_rejected_same_error_as_unknown`, `anon_and_null_uid_rejected`, `unknown_and_owner_keys_rejected`, `same_field_conflict_preserves_both`, `different_fields_merge`, `same_value_edit_is_noop`, `rls_unchanged`.
- [ ] Implement per §3 steps 1–7, 9.

### S3 Server delete, tombstone tree rules, resolve
**Files:** Create `supabase/migrations/<ts>_nexora_sync_delete_resolve.sql`; Test `supabase/tests/sync_tree_test.sql`.
**Interfaces — Produces:** delete handling in `apply_operation`; `nexora_resolve_conflict`.
- [ ] Failing tests: `delete_parent_with_live_child_conflicts`, `leaf_first_batch_deletes_tree`, `create_under_tombstoned_parent_conflicts`, `concurrent_move_cycle_conflicts`, `edit_after_delete_conflicts_no_undelete`, `delete_after_edit_conflicts`, `resolve_is_idempotent`, `resolution_keeps_both_values`.
- [ ] Implement.

### S4 Server pull and cursor concurrency
**Files:** Create `supabase/migrations/<ts>_nexora_sync_pull.sql`; Test `supabase/tests/concurrency/` (multi-connection harness, runs `psql` sessions from a script).
**Interfaces — Produces:** `nexora_sync_pull`.
- [ ] Failing tests: `uncommitted_writer_blocks_second_writer_so_no_gap`, `pull_during_open_push_never_skips`, `pagination_resumes_without_duplicates_or_gaps`, `tombstones_are_returned`, `other_user_rows_never_returned`.
- [ ] Implement; confirm tests fail if the advisory lock is removed (negative control).

### S5 SQLite outbox v2 (Phase 2A owner)
- [ ] Their migration v2 per §4.2 with tests: `domain_write_and_outbox_row_atomic`, `crash_in_flight_returns_to_pending`, `seq_order_survives_restart`, `db_bound_to_single_user`.

### S6 Dart sync engine against a fake transport
**Files:** Create `lib/features/sync/domain/`, `lib/features/sync/application/sync_engine.dart`, `test/features/sync/`.
**Interfaces — Produces:**
```dart
abstract interface class SyncTransport {
  Future<PushResponse> push(String deviceId, List<OutboxOp> ops);
  Future<PullResponse> pull(String deviceId, int cursor, int limit);
  Future<ResolveResponse> resolve(ResolveRequest request);
}
abstract interface class OutboxStore {
  Future<List<OutboxOp>> claimBatch(int max);          // pending -> in_flight, one txn
  Future<void> recordResult(OutboxResult result);
  Future<void> requeueInFlight();
}
final class SyncEngine { Future<SyncReport> runOnce(); }
```
- [ ] Failing tests with an in-memory fake that implements §3 (shared scenario table, see §7 contract tests): retry, backoff, held ops, conflict storage, pull-not-overwriting-dirty-fields.
- [ ] Implement. Pure Dart; no network package inside domain/application.

### S7 Auth, device and session (needs dependency approval, D-S)
- [ ] Failing tests: expired token pauses and keeps ops; user change refused with pending ops; logout policy (local data kept, sync stops); device id created once and persisted; tokens stored device-private.

### S8 End-to-end two-device and failure injection against disposable PostgreSQL 17
- [ ] Run the full matrix in §7 with the real RPCs. See acceptance criteria.

### S9 Activation gate (separate owner approval, separate migration)
- [ ] Migration revoking INSERT/UPDATE on `projects`/`tasks` from `authenticated`; grant EXECUTE on the four wrappers; flag stays OFF in the shipped build until the owner flips it. Rollback: flag OFF and revoke wrappers (tables untouched).
- [ ] Hosted verification: rollback-only suite, Advisors, ACL and grant dump.

## 7. Test strategy
- **Server SQL suites** (`supabase/tests/*.sql`): same rollback harness as Phase 2B, two or three identities, run on disposable PostgreSQL 17 (Docker `postgres:17` in CI plus the Supabase role fixture). Hosted runs only the rollback-safe subset.
- **Concurrency harness:** several `psql` sessions driven by a script; one session keeps an uncommitted push open while another pulls and pushes (gap, blocking and duplicate-race tests).
- **Shared scenario table:** one list of `(initial state, ops per device, expected rows, expected conflicts)` executed against (a) the Dart in-memory fake and (b) the real RPCs. A divergence fails CI, so the fake cannot drift.
- **Property test:** random operation sequences on 2–3 simulated devices with random delays, drops and replays; after quiescence all devices equal the server and every conflict row is present.
- **Failure injection:** client killed after server commit and before ack; response dropped; kill between SQLite domain write and outbox insert (inject fault inside the transaction); `in_flight` rows at restart; server error on op k of n; JWT expired mid-push; revoked device; clock skew ±1 day on `client_created_at`; 1000-op batch rejected, 100-op batch accepted; 256 KB notes accepted, over-limit rejected.
- **Security matrix:** cross-user `operation_id` probing, foreign `entity_id` (indistinguishable from missing), foreign `device_id`, spoofed `owner_id`/`user_id`, anonymous and `anon` role, after S9 direct table write denied, `project_members` row grants nothing, wrapper ACLs exact.
- **Client:** Windows CI runs repository and engine integration tests on a real SQLite file; the end-to-end process restart test remains a manual or `integration_test` step (see 2A §7).

## 8. Decisions for the owner
| ID | Decision | Options | Recommendation |
|---|---|---|---|
| D-C | Conflict granularity | row-level; field-level via `field_versions` | Field-level (new column, S1) |
| D-A | Operation atomicity | partial apply of non-conflicting fields; whole op | Whole op: conflicting op applies nothing |
| D-P | Parent delete | server cascade; explicit leaf-first from client plus server rejection | Explicit; never silent cascade |
| D-L | Pull safety | advisory lock plus revoked direct writes; xid fence; overlap window | Advisory lock (+ SG5); xid fence as fallback |
| D-R | RPC exposure | definer in `public`; invoker wrapper over private definer | Invoker wrapper (zero Advisor findings) |
| D-V | Local `version` | server-owned; locally incremented | Server-owned (requires 2A change) |
| D-T | Tombstones | revertible; permanent; compaction | Permanent, no compaction in V1; revisit with size data |
| D-E | Update after delete | resurrect; conflict | Conflict; resolve by server or recreate-as-copy |
| D-O | `sort_order` conflicts | prompt user; auto-resolve server-wins | Record a conflict row but auto-resolve `resolved_server` (nothing lost, no prompt) |
| D-N | Notes merge | whole-field conflict; text merge | Whole-field conflict in V1; manual merge editor later |
| D-S | Client dependencies | `supabase_flutter`; raw `http` + token handling; secure token store (`flutter_secure_storage` or DPAPI) | Needs approval; recommend `supabase_flutter` pinned plus Windows secure storage |
| D-U | Auth configuration | check anonymous sign-ins and public sign-up in the dashboard | Disable anonymous sign-in; RPC also rejects `is_anonymous` JWTs. Owner must confirm the dashboard setting; I cannot read it |
| D-D | Device policy | unlimited; capped | Cap 10 active, revocable |
| D-X | Test environment | hosted branch; Docker PG17; hosted rollback only | Docker PG17 in CI; hosted rollback-only |
| D-F | Feature flag | build-time; remote | Build-time, default OFF |

## 9. Acceptance criteria
- **AC-1** Replay of any operation any number of times yields one version bump and an identical result.
- **AC-2** Crash at any point between local commit and ack loses nothing and duplicates nothing.
- **AC-3** Concurrent same-field edits produce one conflict row holding both values; neither device's value is lost; resolution works from either device.
- **AC-4** Concurrent edits to different fields converge without conflict.
- **AC-5** Parent delete with a concurrently added or edited child produces a conflict, never a silent delete; the tree has no orphans or cycles after convergence.
- **AC-6** A pull with a concurrent writer returns every committed row exactly once across pages (negative control fails without the lock).
- **AC-7** After full sync, all devices equal the server (property test, ≥ 500 random scenarios, zero divergence).
- **AC-8** Offline for any duration then reconnect: queue drains in order; expired token keeps the queue.
- **AC-9** A database bound to user A never pushes under user B.
- **AC-10** Device clocks have no effect on results.

## 10. Security gates (all must pass before activation)
- **SG1** No service-role key in client, CI or repo (secret scan in CI).
- **SG2** User identity only from `auth.uid()`; null and anonymous rejected.
- **SG3** Wrapper ACL exactly: no `PUBLIC`, no `anon`, `authenticated` only; private functions not executable by clients.
- **SG4** Cross-user matrix green; foreign and missing entities indistinguishable.
- **SG5** Direct writes to `projects` and `tasks` revoked from `authenticated` (S9).
- **SG6** Patch whitelist and size limits enforced; statement timeout set on RPCs.
- **SG7** Supabase Security Advisor: zero findings after each migration; Performance Advisor reviewed.
- **SG8** `project_members` remains inert; sharing tests green.
- **SG9** Local DB bound to one user; tokens stored device-private; logout policy documented.
- **SG10** No persistent test users or data on hosted; every hosted test ends in rollback.
- **SG11** Hosted regression (existing 57 plus new suites) green on PostgreSQL 17 before and after each migration.
- **SG12** Activation requires separate written owner approval; flag default OFF; documented rollback.

## 11. Risks
- Advisory-lock discipline is a correctness dependency; mitigated by SG5 and the negative-control test.
- `field_versions` adds write cost per update; negligible at V1 scale.
- Phase 2A drift (version semantics, outbox shape) is the largest coordination risk; S0 resolves it before code.
- Long-running hosted transactions can delay writers behind the per-user lock; statement timeout bounds this.
- Tombstones grow without compaction; monitor.

## 12. Recommended order
S0 → S1 → S2 → S3 → S4 (server complete, no client) → S5 ∥ S6 (client against the fake) → S7 → S8 → S9. Each slice is its own branch and PR with tests first. The server slices S1–S4 need no client dependency and can start as soon as D-C, D-A, D-P, D-L, D-R and D-T are approved.
