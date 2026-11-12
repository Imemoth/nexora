# Security and migration review: Phase 3 S1 (`20261112130000_nexora_sync_protocol_schema`)

Scope: local review and tests only. **Not applied to the hosted project.** Test results are from local PostgreSQL 16.15 (PostgreSQL 17 pending, see the report).

## Migration safety
| Check | Result |
|---|---|
| Additive | New columns, functions, triggers, indexes; no table or column dropped |
| Replaces existing objects | `guard_row()` (CREATE OR REPLACE) and FK `sync_operations_device_id_user_id_fkey` (RESTRICT -> NO ACTION). Both reviewed; guard aborts if any sync row exists |
| Data-dependent | Aborts with an exception when `sync_conflicts`, `sync_operations` or `devices` is non-empty (all empty on hosted) |
| Grants | No grant or revoke on tables; no direct-write permission change; no RPC; flag untouched |
| Re-run | Fails loudly (objects exist); not idempotent by design |

## Findings
| # | Severity | Finding | Status |
|---|---|---|---|
| F1 | Medium (functional) | Phase 2B `guard_row` raises 42703 on any UPDATE of `public.projects` (hosted today). Not exposed as a security hole; blocks project edits and soft delete | Fixed in S1; reproduced before, passes after |
| F2 | Medium (design) | Taking a per-user lock inside a BEFORE trigger before RLS `WITH CHECK` would let a client with a forged `owner_id` wait on or hold a victim's lock | Fixed: owner mismatch rejected before locking; concurrency scenario C |
| F3 | Medium | `session_replication_role = replica` (allowed for privileged roles on Supabase) would skip guards, versioning and lock | Mitigated: guard triggers are `ENABLE ALWAYS`; tested |
| F4 | Low | Lock key is a 64-bit hash of the user id; a collision only serializes two users briefly | Accepted |
| F5 | Low | Append-only enforcement uses `pg_trigger_depth()` so account deletion can cascade; a nested trigger could bypass it. Grants (no client DML) remain the real boundary | Accepted; documented |
| F6 | Low | Writers touching two different users in one transaction can deadlock | Not a V1 path; documented |
| F7 | Info | Anonymous or self sign-up users would hold a real `auth.uid()`. Auth settings are unverified (D-U) | Open; owner audit before auth activation |
| F8 | Info | Local fixture is a reconstruction; hosted verification of S1 still required before any activation | Open |

## D-L conditions
- Multi-session test with negative control: `supabase/tests/concurrency/lock_discipline.sh` (A complete, B gap without lock, C forged owner).
- All write paths follow the lock: authenticated direct DML, service_role and postgres verified by `pg_locks`; coverage test asserts every table with `change_seq` has an `ENABLE ALWAYS` guard; future RPCs inherit it from the trigger.
- Not covered by the trigger: sessions that disable triggers (`ALTER TABLE ... DISABLE TRIGGER`, needs ownership) and hard deletes. Neither assigns `change_seq`.

## D-R conditions (S2 gate, not applicable to S1)
S1 adds no wrapper. `nexora_private` functions have no client EXECUTE (`revoke ... from public, anon, authenticated`; client call attempts return 42501 in tests). S2 must verify wrapper ACLs, `search_path = ''`, ownership checks, and non-exposure.

## D-O conditions
`resolution_source`, `resolution_policy` (only `sort_order_server_wins`), `resolution_operation_id`; preserved values immutable; `sync_operations` append-only; resolved conflicts final. Tested.
