# Supabase Access Verification (Phase 0)

Status: **PASS** (read-only), verified 2026-11-11.

## Target
- Project reference: `uicccaawtjvqggeufbez`
- Access path: the Nexora-specific Supabase MCP connector (local name `supabase-nexora`, read-only mode).

## Verified checks (read-only)
| Check | Result | Evidence |
|---|---|---|
| Connector is reachable and authorized | PASS | `claude mcp list` shows `supabase-nexora` connected |
| Project metadata matches the target | PASS | `get_project_url` returned the host for `uicccaawtjvqggeufbez` |
| Migration history | PASS (empty) | `list_migrations` returned no entries |
| Schema inventory | PASS | `information_schema.schemata` returned the standard Supabase schemas plus `public` |
| `public` tables | PASS (zero) | `list_tables(public)` returned no tables |
| RLS policies in `public` | PASS (zero) | `pg_policies` count for `public` = 0 |
| Read-only URL parameter | PASS | Configured URL contains `read_only=true` |
| Server-side read-only enforcement | UNKNOWN | Not independently verified. Do not treat the URL flag as proof |

## Mutations performed
None. No migrations, DDL, DML, deployments, configuration changes, or credential changes.

## Expected state for Phase 0
An empty `public` schema and an empty migration history are expected. Phase 0 contains no hosted migrations.

## Gate for later phases
- Any hosted migration, secret change, or deployment requires explicit owner approval, recorded separately.
- Re-run the read-only checks above before any hosted change. Do not reuse this record as evidence for later changes.
- A check that fails or cannot be run is recorded as `BLOCKED`, not `PASS`.
- The service-role key must never be used in client code, CI, or the repository.
