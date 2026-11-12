# Sync foundation design (Phase 2B) — schema only, sync NOT active

## Objects (migration `20261112120200`)
`devices(id,user_id,…)`, `sync_operations(user_id,operation_id PK, device_id, entity_type, entity_id, op_type, base_version, patch, request_hash, status, result, applied_version, server_seq,…)`, `sync_conflicts(id,user_id,operation_id,entity_type,entity_id,fields[],base_version,server_version,server_value,client_value,status,resolved_at)`.
All have RLS; authenticated users have SELECT on own rows only; no client INSERT/UPDATE/DELETE; anon nothing. No RPC exists, so nothing can be written.

## Authorization rule for the future RPC (Phase 3)
`nexora_private.apply_operation(...)` SECURITY DEFINER, `search_path=''`, in a non-exposed schema with a thin SECURITY INVOKER wrapper in `public` granted to `authenticated` only. It must: take `user_id := auth.uid()` (reject null), verify `device_id` belongs to that user and is not revoked (composite FK + check), verify the entity's `owner_id = user_id` before any write, never accept `user_id`/`owner_id` from the payload, and whitelist patch fields per entity type. A guessed `operation_id` of another user is harmless: the PK is per user.

## Transaction boundary
One operation = one transaction: lock entity row `FOR UPDATE`, check `base_version`, apply or write conflict, insert `sync_operations` row with the stored result, commit. Insert of the operation row is the idempotency gate (`ON CONFLICT (user_id, operation_id) DO NOTHING` then read the stored row). Batches are per-operation transactions so one bad op does not block others; ordering within a batch is preserved by the client.

## Retry safety
Replay returns the stored `result` verbatim. Network loss after commit is therefore safe. Conflicts are results, not errors.

## Remaining Phase 3 decisions
Field-level merge rules; parent-delete handling; tombstone compaction (decided: none in V1); device registration/revocation flow; Realtime (not needed for V1). Pull safety is decided (D-L, per-user advisory lock; see `data-contract.md`). Required tests before activation: two-device replay, conflict preservation, cross-user operation_id probing, expired token, out-of-order pagination.
