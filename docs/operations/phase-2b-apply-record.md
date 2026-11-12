# Phase 2B hosted apply record (2026-11-12)

Project `uicccaawtjvqggeufbez` (PostgreSQL 17.11). Repo HEAD at apply time: `1389dd5aeb006763c44cc7a4b3d49222c195b532`. Owner decisions: D1 approved, D2 conditional (gates passed).
Connector: project-scoped write connector (`Supabase_Nexora_Dev`), verified to return the project URL for the target ref. No permission failure was bypassed.

| Version | Name | SHA-256 (prefix) |
|---|---|---|
| 20261112115809 | nexora_security_hardening | 0a4241a061199437 |
| 20261112120132 | nexora_contract_alignment | 1f75f60b197a6887 |
| 20261112120149 | nexora_sync_foundation | fa9365a5accd10f7 |

Verification: migration history lists 4 entries; RLS on 7 tables; `anon` has no table grants; `authenticated` has no DELETE and no `project_members` access; `rls_auto_enable` ACL = postgres, service_role only and `ensure_rls` still enabled; guard triggers present. Regression suite `supabase/tests/rls_and_contract_test.sql`: 57/57 pass on hosted, rolled back (0 users/projects/tasks/devices/operations afterwards; `nexora_private.change_seq` advanced to 18 because sequences are not transactional). Security Advisor: 0 findings. Performance Advisor: INFO only.

Correction to the earlier audit: the initial schema already had `profiles_updated_at`, `projects_updated_at`, `tasks_updated_at` triggers using `nexora_set_updated_at()`. They coexist with the new guard triggers (same value, harmless); `nexora_set_updated_at` is in use and must not be dropped.
