-- Phase 2B / 1 of 3: security hardening. Additive/restrictive only; no data or objects dropped
-- except two redundant DELETE policies (hard delete is replaced by tombstones, see data contract).

-- 1. rls_auto_enable() is an event-trigger function. Event triggers do not check the firing role's
--    EXECUTE privilege, so revoking client roles cannot break ensure_rls. Trigger, function and
--    schema location are intentionally left unchanged.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;

-- 2. Default-deny table grants (RLS stays enabled as the second layer).
revoke all on public.profiles, public.projects, public.tasks, public.project_members from anon;
revoke all on public.profiles, public.projects, public.tasks, public.project_members from authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.projects to authenticated;   -- no DELETE: soft-delete tombstones only
grant select, insert, update on public.tasks    to authenticated;   -- no DELETE: soft-delete tombstones only
-- project_members: no client privileges in V1 (sharing inactive). Policies remain but are inert.
drop policy if exists projects_owner_delete on public.projects;
drop policy if exists tasks_owner_delete on public.tasks;

-- 3. Future objects created by postgres in public are not auto-granted to anon / client functions.
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;
