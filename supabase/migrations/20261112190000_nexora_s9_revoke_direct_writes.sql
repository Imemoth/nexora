-- S9: remove every direct write path to the synchronized tables. After this migration the only way to change
-- public.projects, public.tasks or public.project_members as a client is through the synchronization RPCs
-- (SECURITY DEFINER, owned by postgres, unaffected by client table privileges).
-- Kept on purpose: SELECT (reads stay under RLS), every privilege on public.profiles, service_role, and all RLS policies
-- (they become inert for writes and keep the catalog diff small). Local and CI tested; NOT applied to hosted.
-- Rollback: supabase/rollback/20261112190000_rollback_s9_direct_writes.sql (restores INSERT and UPDATE on projects and
-- tasks for authenticated, the exact pre-S9 grants; no data is touched in either direction).
-- Plan and deviations: docs/operations/s9-direct-grants-removal-plan.md.
revoke insert, update, delete, truncate, references, trigger
  on public.projects, public.tasks, public.project_members
  from public, anon, authenticated;
