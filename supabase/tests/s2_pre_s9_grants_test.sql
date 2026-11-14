-- Pre-S9 grant state. Runs on the database BEFORE the S9 migration (run_local.sh order). Rollback-only.
-- This is the original 'direct_table_grants_unchanged_by_s2_s3_s4' assertion, kept true for the pre-S9 state so that
-- S9 is the only thing that ever changes it (s2_auth_grants_test.sql asserts the post-S9 state).
begin;
\ir s2_helpers.sql
do $$
begin
  perform pg_temp.assert('direct_table_grants_unchanged_by_s2_s3_s4_and_throttle',
    (select string_agg(table_name || ':' || privilege_type, ',' order by table_name, privilege_type)
       from information_schema.role_table_grants where table_schema='public' and grantee='authenticated')
    = 'devices:SELECT,profiles:INSERT,profiles:SELECT,profiles:UPDATE,projects:INSERT,projects:SELECT,projects:UPDATE,sync_conflicts:SELECT,sync_operations:SELECT,tasks:INSERT,tasks:SELECT,tasks:UPDATE');
  perform pg_temp.assert('pre_s9_anon_has_no_table_grants',
    not exists (select 1 from information_schema.role_table_grants where table_schema='public' and grantee='anon'));
  perform pg_temp.assert('pre_s9_project_members_has_no_client_privileges',
    not exists (select 1 from information_schema.role_table_grants where table_schema='public' and table_name='project_members' and grantee in ('authenticated','anon')));
end $$;
select count(*) as passed from _r;
rollback;
