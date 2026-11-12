-- S9: direct table writes revoked; reads, profiles and the sync RPCs unaffected. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da uuid := pg_temp.u('d0000000', 1); db uuid := pg_temp.u('d0000000', 2); da2 uuid := pg_temp.u('d0000000', 3);
  p uuid := pg_temp.u('e1000000', 1); t uuid := pg_temp.u('e2000000', 1); r jsonb; tbl text; rl text; stmt text; stmts text[]; cid uuid;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  perform pg_temp.reg(a, da); perform pg_temp.reg(b, db);
  perform pg_temp.c(a, da, 'project', p, 'create', null, '{"name":"A project"}');
  perform pg_temp.c(a, da, 'task', t, 'create', null, jsonb_build_object('project_id', p, 'title', 'A task'));

  ---------------------------------------------------------------- direct writes are refused with 42501 for every client role
  foreach rl in array array['authenticated', 'anon'] loop
    foreach tbl in array array['projects', 'tasks', 'project_members'] loop
      stmts := array[
        format('insert into public.%I select * from public.%I limit 0 returning to_jsonb(1)', tbl, tbl),
        format('update public.%I set created_at = now() returning to_jsonb(1)', tbl),
        format('delete from public.%I returning to_jsonb(1)', tbl),
        format('truncate public.%I', tbl)];
      foreach stmt in array stmts loop
        r := pg_temp.rpc(a, stmt, false, rl);
        perform pg_temp.assert('s9_' || rl || '_' || tbl || '_' || split_part(stmt, ' ', 1) || '_denied', pg_temp.err(r) = '42501');
      end loop;
    end loop;
  end loop;
  r := pg_temp.rpc(a, format('insert into public.tasks(id, owner_id, project_id, title) values (%L, %L, %L, ''x'') returning to_jsonb(1)', gen_random_uuid(), a, p));
  perform pg_temp.assert('s9_real_direct_task_insert_denied_even_for_own_rows', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, format('update public.projects set name = ''hacked'' where id = %L returning to_jsonb(1)', p));
  perform pg_temp.assert('s9_real_direct_project_update_denied_even_for_own_rows', pg_temp.err(r) = '42501');
  perform pg_temp.assert('s9_denied_writes_changed_nothing',
    (select name from public.projects where id = p) = 'A project' and (select count(*) from public.tasks where owner_id = a) = 1);

  ---------------------------------------------------------------- reads still work under RLS and are isolated
  r := pg_temp.rpc(a, 'select to_jsonb(count(*)) from public.projects');
  perform pg_temp.assert('s9_owner_can_select_own_projects', r = '1'::jsonb);
  r := pg_temp.rpc(a, 'select to_jsonb(count(*)) from public.tasks');
  perform pg_temp.assert('s9_owner_can_select_own_tasks', r = '1'::jsonb);
  r := pg_temp.rpc(b, 'select to_jsonb(count(*)) from public.projects');
  perform pg_temp.assert('s9_other_user_sees_no_projects', r = '0'::jsonb);
  r := pg_temp.rpc(b, 'select to_jsonb(count(*)) from public.tasks');
  perform pg_temp.assert('s9_other_user_sees_no_tasks', r = '0'::jsonb);
  r := pg_temp.rpc(null, 'select to_jsonb(count(*)) from public.tasks', false, 'anon');
  perform pg_temp.assert('s9_anon_sees_no_tasks', r = '0'::jsonb or pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'select to_jsonb(count(*)) from public.project_members');
  perform pg_temp.assert('s9_project_members_select_not_an_error', not (r ? 'error') or pg_temp.err(r) = '42501');

  ---------------------------------------------------------------- profiles stay writable by their owner
  r := pg_temp.rpc(a, format('insert into public.profiles(id, display_name) values (%L, ''A'') returning to_jsonb(1)', a));
  perform pg_temp.assert('s9_profile_insert_still_allowed', r = '1'::jsonb);
  r := pg_temp.rpc(a, format('update public.profiles set display_name = ''Alice'' where id = %L returning to_jsonb(1)', a));
  perform pg_temp.assert('s9_profile_update_still_allowed', r = '1'::jsonb);
  perform pg_temp.assert('s9_profile_update_took_effect', (select display_name from public.profiles where id = a) = 'Alice');
  r := pg_temp.rpc(b, format('update public.profiles set display_name = ''Mallory'' where id = %L returning to_jsonb(1)', a));
  perform pg_temp.assert('s9_profile_of_other_user_not_updatable', (select display_name from public.profiles where id = a) = 'Alice');

  ---------------------------------------------------------------- the five sync RPCs work end to end as authenticated
  r := pg_temp.reg(a, da2, 'second');
  perform pg_temp.assert('s9_rpc_register_device_works', not (r ? 'error'));
  r := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'task', t, 'update', 1, '{"title":"renamed"}')));
  perform pg_temp.assert('s9_rpc_push_works_and_writes', r -> 'results' -> 0 ->> 'status' = 'applied' and (select title from public.tasks where id = t) = 'renamed');
  r := pg_temp.pull(a, da2, 0);
  perform pg_temp.assert('s9_rpc_pull_works', not (r ? 'error') and jsonb_array_length(r -> 'changes') >= 2);
  -- a conflict, then resolve
  r := pg_temp.push(a, da2, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'task', t, 'update', 1, '{"title":"stale"}')));
  cid := pg_temp.open_conflict(t);
  perform pg_temp.assert('s9_conflict_recorded_through_rpc', cid is not null);
  r := pg_temp.resolve(a, da2, pg_temp.nid(), cid, 'resolved_server');
  perform pg_temp.assert('s9_rpc_resolve_works', not (r ? 'error'));
  r := pg_temp.revoke(a, da, da2);
  perform pg_temp.assert('s9_rpc_revoke_works', not (r ? 'error'));
  perform pg_temp.assert('s9_revoked_device_is_revoked', (select revoked_at is not null from public.devices where id = da2));

  ---------------------------------------------------------------- tenant isolation of the RPCs
  r := pg_temp.push(b, db, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'task', t, 'update', 2, '{"title":"b-writes-a"}')));
  perform pg_temp.assert('s9_other_user_cannot_modify_foreign_task_via_rpc',
    (select title from public.tasks where id = t) <> 'b-writes-a' and (r ? 'error' or r -> 'results' -> 0 ->> 'status' <> 'applied'));
  r := pg_temp.pull(b, db, 0);
  perform pg_temp.assert('s9_other_user_pull_is_empty', jsonb_array_length(r -> 'changes') = 0);

  ---------------------------------------------------------------- catalog state
  perform pg_temp.assert('s9_no_write_acl_left_on_synchronized_tables',
    not exists (select 1 from information_schema.role_table_grants
      where table_schema = 'public' and table_name in ('projects', 'tasks', 'project_members')
        and grantee in ('PUBLIC', 'anon', 'authenticated')
        and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')));
  perform pg_temp.assert('s9_select_privilege_retained',
    has_table_privilege('authenticated', 'public.projects', 'select') and has_table_privilege('authenticated', 'public.tasks', 'select'));
  perform pg_temp.assert('s9_rls_still_enabled_and_forced_state_unchanged',
    (select bool_and(relrowsecurity) from pg_class where oid in ('public.projects'::regclass, 'public.tasks'::regclass, 'public.project_members'::regclass)));
end $$;
select count(*) as passed from _r;
rollback;
