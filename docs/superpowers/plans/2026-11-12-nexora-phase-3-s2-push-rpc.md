# Nexora Phase 3 S2 Implementation Plan: device registration and idempotent push

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Status: PLAN ONLY. Nothing here is implemented, applied, exposed or activated.** S2 needs separate owner approval to start, and S1 must be applied and verified on hosted before S2 is applied (S2 relies on `field_versions`, the append-only log and the device cap). Local development on a disposable database can start earlier.

**Goal:** a signed-in user's device can register itself and push batches of create/update operations that are applied at most once, with field-level conflict detection and no cross-user access.

**Architecture:** two thin SECURITY INVOKER wrappers in `public` call SECURITY DEFINER implementations in `nexora_private` (D-R). The implementation derives the user only from `auth.uid()`, takes the per-user advisory lock once per call, and applies each operation in its own sub-transaction. The operation log row (append-only) is written once with its final result.

**Tech Stack:** PostgreSQL 17, PL/pgSQL, the existing rollback SQL suites plus the multi-session harness.

**Spec:** `docs/superpowers/plans/2026-11-12-nexora-phase-3-sync.md` (sections 2 and 3), `docs/architecture/data-contract.md`, `docs/architecture/decisions/0002-sync-protocol.md`, `docs/operations/s1-hosted-deployment-gate.md`.

## Global Constraints
- D-R conditions: verify exact EXECUTE privileges, `search_path`, ownership checks, and that `nexora_private` is not exposed.
- The user comes only from `auth.uid()`; null and anonymous JWTs are rejected. `owner_id`, `user_id`, `version`, `field_versions`, `change_seq`, `created_at`, `updated_at` are never accepted from a payload.
- Synchronization stays disabled: S2 adds functions only. No grant change on tables, no RLS change, no Auth change.
- Limits: at most 100 operations per call, patch at most 256 KB, whole call at most 1 MB, `statement_timeout` 10 s and `lock_timeout` 5 s set on the function.
- No `SELECT`/`INSERT` of `sync_operations` by clients (unchanged: read-only on own rows).

## Plan amendments discovered while preparing S2 (versus the Phase 3 plan)
1. **Idempotency gate order.** The Phase 3 plan inserted the operation row first (`ON CONFLICT DO NOTHING`) and filled `result` later. S1 made `sync_operations` append-only, so the row cannot be updated. S2 therefore does: take the per-user lock, look up the stored operation, apply, then insert the row once with its final `result`. Concurrent duplicates cannot race: the second call blocks on the user lock until the first commits and then finds the stored row. The primary key stays as the backstop.
2. **Rejected versus transient errors.** Terminal errors (validation, forbidden, not found) are recorded as `rejected` rows so a replay returns the same answer. Transient errors (40001, 40P01, 55P03, 57014) are not recorded and abort the whole call; the client retries the whole batch.
3. **Delete and resolve** stay in S3. S2 covers register, create, update and the conflicts they produce (`field`, `edit_deleted`, `exists`).

## Review Focus
- A retry after a lost response returns the stored result and changes nothing.
- An operation targeting another user's entity is indistinguishable from a missing one (same response body).
- A failing operation in a batch leaves no partial row, version bump or `field_versions` entry from that operation.
- A forged owner, user or version key in a patch is rejected, never silently ignored.
- The wrappers have exactly the intended privileges and `nexora_private` is not reachable through the Data API.

## Public and private objects
| Object | Kind | Security | Notes |
|---|---|---|---|
| `public.nexora_register_device(p_device_id uuid, p_label text default null) returns jsonb` | wrapper | INVOKER, `search_path=''` | `select nexora_private.register_device(p_device_id, p_label)` |
| `public.nexora_sync_push(p_device_id uuid, p_ops jsonb) returns jsonb` | wrapper | INVOKER, `search_path=''` | `select nexora_private.push(p_device_id, p_ops)` |
| `nexora_private.sync_user() returns uuid` | helper | INVOKER | `auth.uid()`; raises `28000` if null; raises `42501` if the JWT claim `is_anonymous` is true |
| `nexora_private.register_device(uuid, text) returns jsonb` | entry point | DEFINER, `search_path=''` | locks user, inserts or returns the device |
| `nexora_private.push(uuid, jsonb) returns jsonb` | entry point | DEFINER, `search_path=''`, `statement_timeout`/`lock_timeout` set | batch loop |
| `nexora_private.apply_operation(uuid, uuid, jsonb) returns jsonb` | internal | DEFINER, `search_path=''` | one operation, called only by `push` |

**Exact EXECUTE grants** (everything else revoked from `public`, `anon`, `authenticated`; `service_role` gets none):
| Function | `authenticated` | `anon` | `public` |
|---|---|---|---|
| `public.nexora_register_device`, `public.nexora_sync_push` | EXECUTE | none | none |
| `nexora_private.register_device`, `nexora_private.push` | EXECUTE | none | none |
| `nexora_private.apply_operation`, `sync_user`, S1 functions | none | none | none |
`authenticated` additionally needs `USAGE` on schema `nexora_private` (the invoker wrapper calls into it); `anon` has none. `nexora_private` stays out of the Data API's exposed schemas (test asserts the `authenticator` role setting).

## Operation semantics (create and update)
Op: `{operation_id, entity_type, entity_id, op_type, base_version, patch, client_created_at}`. Result: `{operation_id, status: applied|conflict|rejected, applied_version, row, conflict_id, error_code, replayed}`.
- Allowed patch keys: project `name, description, color, is_archived, sort_order`; task `parent_id, title, notes, status, priority, due_date, completed_at, sort_order`; create also `project_id` (task). Any other key: `rejected: invalid_patch`.
- `create`: the entity must not exist; a task needs a live project owned by the caller and, if present, a live same-project parent. Existing id: identical content is `applied` as a no-op replay of the create's effect, different content is a conflict of kind `exists`.
- `update`: load `where owner_id = caller`; not found or foreign is `rejected: not_found`. Tombstoned is a conflict of kind `edit_deleted`. A patched field conflicts only if `field_versions[f] > base_version` and the current value differs; equal values and disjoint fields merge. A conflicting operation applies nothing and writes one `sync_conflicts` row with `server_value`, `client_value`, `fields`, `base_version`, `server_version`.
- Replay: same `(user_id, operation_id)` and same `request_hash` returns the stored result with `replayed=true`; same id with a different hash is `rejected: operation_id_reuse`. `request_hash = encode(sha256(convert_to(entity_type||'|'||entity_id||'|'||op_type||'|'||coalesce(base_version::text,'')||'|'||patch::text,'utf8')),'hex')` (jsonb text is canonical).
- An entity with an open conflict from this user returns `rejected: blocked_by_conflict` for later operations.
- Error codes: `unauthenticated, anonymous_not_allowed, device_invalid, device_limit, batch_too_large, payload_too_large, invalid_op, invalid_patch, operation_id_reuse, not_found, blocked_by_conflict, parent_invalid`. Unknown and foreign devices share `device_invalid`.

## File structure
- Create `supabase/migrations/<ts>_nexora_sync_push.sql`: the six objects and grants above.
- Create `supabase/tests/s2_*_test.sql`: rollback suites (one file per topic) using a JWT helper that sets `request.jwt.claims` including `is_anonymous`.
- Create `supabase/tests/concurrency/s2_duplicate_push.sh`: multi-session duplicate and lock tests.
- Create `supabase/rollback/<ts>_rollback_s2_sync_push.sql` (drops the six functions; verified to restore the S1 catalog).
- Modify `supabase/tests/run_local.sh` only to pick up the new suites; the workflow file and S1 files stay unchanged.

## Test matrix (IDs are test names; each is a rollback-only assertion unless marked MS = multi-session)
| Area | Tests |
|---|---|
| Authentication | `null_uid_rejected`, `anon_role_has_no_execute`, `anonymous_jwt_rejected`, `revoked_device_rejected`, `foreign_device_same_error_as_unknown` |
| Exact grants | `wrappers_are_invoker_with_empty_search_path`, `private_entry_points_definer_with_empty_search_path`, `execute_acl_matches_matrix` (full ACL equality), `apply_operation_not_executable_by_clients`, `nexora_private_not_in_exposed_schemas`, `no_new_public_definer_functions` |
| Device registration | `register_is_idempotent`, `register_other_users_device_id_rejected`, `device_limit_enforced_via_wrapper`, `label_length_enforced` |
| Idempotency and replay | `replay_returns_stored_result_once`, `replay_does_not_bump_version_or_change_seq`, `same_id_different_hash_rejected`, `same_operation_id_other_user_independent`, `replay_from_second_device_of_same_user`, `partial_batch_replay_applies_only_new_ops`, `rejected_op_replays_as_rejected`, `MS: concurrent_duplicate_applies_once` |
| Batch atomicity | `one_bad_op_does_not_block_others`, `failed_op_leaves_no_partial_change`, `transient_error_aborts_whole_batch_and_records_nothing`, `terminal_error_recorded_as_rejected`, `batch_of_101_rejected`, `patch_over_256kb_rejected`, `call_over_1mb_rejected` |
| Field-level conflicts | `same_field_different_value_conflicts`, `same_field_same_value_is_noop_applied`, `different_fields_merge`, `stale_base_with_untouched_field_applies`, `multi_field_patch_partial_overlap_conflicts_atomically`, `edit_on_tombstone_is_edit_deleted`, `create_existing_identical_is_applied`, `create_existing_different_is_exists_conflict`, `later_op_blocked_by_open_conflict`, `conflict_row_preserves_both_values`, `conflict_row_cross_user_invisible` |
| Rollback behaviour | `error_mid_operation_rolls_back_subtransaction`, `rejected_row_present_after_terminal_error`, `no_row_after_transient_error` |
| Authorization and spoofing | `owner_id_in_patch_rejected`, `user_id_in_patch_rejected`, `version_field_versions_change_seq_in_patch_rejected`, `foreign_entity_same_response_as_missing`, `cross_user_create_in_foreign_project_rejected`, `task_create_with_foreign_parent_rejected`, `direct_table_grants_unchanged_by_s2` |
| Regression | F1 (29), Phase 2B (57) and S1 (43) suites and the S1 concurrency scenarios stay green; the Security Advisor stays at zero findings |

## Tasks
### Task 1: Test harness and fixtures
**Files:** Create `supabase/tests/s2_helpers.sql` (helper functions copied into each suite, same pattern as S1), `supabase/tests/s2_auth_grants_test.sql`.
**Interfaces:** Produces `pg_temp.as_jwt(uid uuid, anonymous boolean)` setting `request.jwt.claims` and role.
- [ ] Write the authentication and exact-grant tests; run them to see them fail (functions absent).
- [ ] Implement `nexora_private.sync_user()` and the grant matrix with stub bodies; run to green.
- [ ] Commit.

### Task 2: Device registration
**Files:** Modify the migration; Create `supabase/tests/s2_device_test.sql`.
**Interfaces:** Produces `nexora_private.register_device(uuid, text) returns jsonb` and the public wrapper.
- [ ] Failing tests: registration matrix above. Implement. Green. Commit.

### Task 3: apply_operation (create, update, conflicts)
**Files:** Modify the migration; Create `supabase/tests/s2_apply_test.sql`.
**Interfaces:** Produces `nexora_private.apply_operation(p_user uuid, p_device uuid, p_op jsonb) returns jsonb`.
- [ ] Failing tests: field-level conflicts and authorization/spoofing rows. Implement per the semantics above. Green. Commit.

### Task 4: push (batch, replay, limits)
**Files:** Modify the migration; Create `supabase/tests/s2_push_test.sql`, `supabase/tests/concurrency/s2_duplicate_push.sh`.
**Interfaces:** Produces `nexora_private.push(uuid, jsonb) returns jsonb` and `public.nexora_sync_push`.
- [ ] Failing tests: idempotency, batch atomicity and the MS duplicate test. Implement. Green on PostgreSQL 17 CI.
- [ ] Negative control for the MS test: with the lock removed the duplicate applies twice.

### Task 5: Rollback script and CI wiring
- [ ] Rollback script drops the six functions; apply after S2 locally and diff the catalog against the S1 state (empty diff).
- [ ] `run_local.sh` runs the new suites; workflow file unchanged.

### Task 6: Hosted deployment gate (only after S1 is applied and S2 is approved)
- [ ] Preflight, optional rollback-only dry run, apply once, catalog diff equals the object table above, rollback-only suites 29/57/43 plus the S2 suites, Advisors zero findings, no persistent data. Stop on any mismatch.

## Entry gates for implementing S2
1. Owner approves starting S2 and the error taxonomy and limits above.
2. D-R conditions accepted as written (invoker wrappers, private definers, `USAGE` on `nexora_private` for `authenticated`).
3. S1 applied and verified on hosted before any S2 hosted apply (local S2 work may proceed on the PostgreSQL 17 CI and a disposable database earlier).
4. D-U (anonymous sign-in and sign-up) audit completed before any authentication or synchronization activation; S2 rejects anonymous JWTs regardless.

## Self-review
Spec coverage: device registration, idempotent push, atomic batches, per-user authorization, exact grants, wrapper and private split, replay and request hash, field-level conflicts, rollback behaviour and unauthorized rejection each map to a task and tests. Consistency: function names and signatures match across the object table, the grant matrix and the tasks. Proportion: the plan lists signatures, semantics and test names; it contains no function bodies.
