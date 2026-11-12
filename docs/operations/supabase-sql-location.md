# Where the Supabase SQL and tests live (as of 2026-11-12)

The shared architecture documents in this repository refer to `supabase/migrations/*`, `supabase/tests/*` and the `supabase-schema-tests` workflow. **Those files were not on `main` when this note was written (2026-11-12) and may still not be.** They live on the development branch `claude/affectionate-turing-unzmd2` (reviewed at `0d20ee6`).

| Item | State | On `main` |
|---|---|---|
| Phase 2B migrations `20261112115809`, `20261112120132`, `20261112120149` | Applied to the hosted project; owner-accepted | No (proposed for a separate owner-approved integration) |
| Standalone fix `20261112125000_nexora_fix_projects_update_guard.sql` | Tested on PostgreSQL 17; **applied to hosted 2026-11-12** as `20261112142732` | No |
| Phase 3 S1 `20261112130000_nexora_sync_protocol_schema.sql` | **Applied to hosted 2026-11-12** as `20261112151851`; not merged to `main` | No |
| SQL regression suites and PostgreSQL 17 workflow | Passing on PostgreSQL 17.11 in CI on the branch (runs 43217510081, 43219771092) | No |
| `docs/operations/security-review-s1.md` | Review of the unapproved S1 SQL | No (stays with the SQL) |

Nothing here applies a migration, changes the hosted project or activates synchronization. Landing the SQL and tests on `main` needs a separate owner decision.
