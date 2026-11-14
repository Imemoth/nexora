-- Rollback of S9: restores the exact pre-S9 direct grants (INSERT and UPDATE on projects and tasks for authenticated;
-- project_members had no client privileges, anon had none). No data is touched.
grant insert, update on public.projects, public.tasks to authenticated;
