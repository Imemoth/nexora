-- S2 authentication, authorization and exact-grant suite. Rollback-only.
begin;
\ir s2_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da uuid := pg_temp.u('d0000000', 1); db uuid := pg_temp.u('d0000000', 2);
  r jsonb; r2 jsonb; ops jsonb;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  ops := jsonb_build_array(pg_temp.op(pg_temp.u('c0000000', 1), 'project', pg_temp.u('e0000000', 1), 'create', null, '{"name":"P"}'));

  -- authentication (JWT claims exactly as PostgREST sets them)
  r := pg_temp.rpc(null, format('select public.nexora_register_device(%L, null)', da));
  perform pg_temp.assert('null_uid_rejected (register)', pg_temp.err(r) = '28000' and pg_temp.msg(r) = 'unauthenticated');
  r := pg_temp.push(null, da, ops);
  perform pg_temp.assert('null_uid_rejected (push)', pg_temp.err(r) = '28000' and pg_temp.msg(r) = 'unauthenticated');
  r := pg_temp.rpc(a, format('select public.nexora_register_device(%L, null)', da), true);
  perform pg_temp.assert('anonymous_jwt_rejected (register)', pg_temp.err(r) = '42501' and pg_temp.msg(r) = 'anonymous_not_allowed');
  r := pg_temp.push(a, da, ops, true);
  perform pg_temp.assert('anonymous_jwt_rejected (push)', pg_temp.err(r) = '42501' and pg_temp.msg(r) = 'anonymous_not_allowed');
  r := pg_temp.rpc(a, format('select public.nexora_register_device(%L, null)', da), false, 'anon');
  perform pg_temp.assert('anon_role_has_no_execute', pg_temp.err(r) = '42501' and pg_temp.msg(r) like 'permission denied%');
  r := pg_temp.rpc(null, format('select public.nexora_register_device(%L, null)', da), false, 'service_role');
  perform pg_temp.assert('service_role_has_no_execute', pg_temp.err(r) = '42501' and pg_temp.msg(r) like 'permission denied%');
  r := pg_temp.rpc(a, 'select nexora_private.apply_operation(gen_random_uuid(), gen_random_uuid(), ''{}''::jsonb)');
  perform pg_temp.assert('apply_operation_not_executable_by_clients', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'select to_jsonb(nexora_private.sync_user())');
  perform pg_temp.assert('sync_user_not_executable_by_clients', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'select nexora_private.guard_row()');
  perform pg_temp.assert('s1_private_functions_still_not_executable', pg_temp.err(r) = '42501');

  -- user-editable claims are never trusted
  r := pg_temp.rpc(a, format('select public.nexora_register_device(%L, null)', da), false, 'authenticated',
        '{"user_metadata": {"sub": "bbbbbbbb-0000-0000-0000-000000000001", "is_anonymous": false, "role": "service_role"}, "app_metadata": {"sub": "bbbbbbbb-0000-0000-0000-000000000001"}}');
  perform pg_temp.assert('metadata_claims_do_not_change_identity', r ->> 'device_id' = da::text
     and (select user_id from public.devices where id = da) = a);
  r := pg_temp.rpc(a, format('select public.nexora_register_device(%L, null)', pg_temp.u('d0000000', 9)), false, 'authenticated',
        '{"user_metadata": {"is_anonymous": true}}');
  perform pg_temp.assert('is_anonymous_only_read_from_top_level_claim', r ->> 'created' = 'true');
  perform pg_temp.mkuser(pg_temp.u('aaaaaaaa', 5));
  delete from auth.users where id = pg_temp.u('aaaaaaaa', 5);
  r := pg_temp.rpc(pg_temp.u('aaaaaaaa', 5), format('select public.nexora_register_device(%L, null)', pg_temp.u('d0000000', 8)));
  perform pg_temp.assert('deleted_user_with_a_valid_token_is_unauthenticated', pg_temp.err(r) = '28000' and not exists (select 1 from public.devices where id = pg_temp.u('d0000000', 8)));
  perform pg_temp.mkuser(pg_temp.u('aaaaaaaa', 6));
  update auth.users set is_anonymous = true where id = pg_temp.u('aaaaaaaa', 6);
  r := pg_temp.rpc(pg_temp.u('aaaaaaaa', 6), format('select public.nexora_register_device(%L, null)', pg_temp.u('d0000000', 8)), false);
  perform pg_temp.assert('anonymous_user_row_rejected_even_when_the_token_claim_says_false', pg_temp.err(r) = '42501' and pg_temp.msg(r) = 'anonymous_not_allowed');
  r := pg_temp.rpc(null, format('select public.nexora_register_device(%L, null)', da), false, 'authenticated', '{"sub": "not-a-uuid"}');
  perform pg_temp.assert('malformed_sub_is_unauthenticated', pg_temp.err(r) = '28000');

  -- device ownership: unknown and foreign devices give the identical error
  perform pg_temp.reg(b, db);
  r := pg_temp.push(a, db, ops);
  r2 := pg_temp.push(a, pg_temp.u('d0000000', 77), ops);
  perform pg_temp.assert('foreign_device_same_error_as_unknown', pg_temp.err(r) = 'NX001' and r = r2);

  -- function shape
  perform pg_temp.assert('wrappers_are_invoker_with_empty_search_path',
    (select count(*) = 2 and bool_and(not prosecdef) and bool_and(proconfig = array['search_path=""'])
       from pg_proc where pronamespace = 'public'::regnamespace and proname in ('nexora_register_device','nexora_sync_push')));
  perform pg_temp.assert('private_entry_points_definer_with_fixed_config',
    (select count(*) = 2 and bool_and(prosecdef) and bool_and(proconfig @> array['search_path=""','lock_timeout=5s'])
         and bool_and(pg_get_userbyid(proowner) = 'postgres')
       from pg_proc where pronamespace = 'nexora_private'::regnamespace and proname in ('register_device','push')));
  perform pg_temp.assert('every_s2_function_has_empty_search_path',
    not exists (select 1 from pg_proc where pronamespace in ('public'::regnamespace,'nexora_private'::regnamespace)
                  and proname in ('nexora_register_device','nexora_sync_push','sync_user','register_device','push','apply_operation','apply_core')
                  and not coalesce(proconfig @> array['search_path=""'], false)));

  -- exact EXECUTE ACL: nothing through PUBLIC, only the reviewed grantees
  perform pg_temp.assert('execute_acl_matches_matrix',
    not exists (
      (select p.oid::regprocedure::text fn, coalesce(a2.grantee::regrole::text, 'PUBLIC') g
         from pg_proc p, lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a2
        where p.pronamespace in ('public'::regnamespace,'nexora_private'::regnamespace) and a2.privilege_type = 'EXECUTE'
       except select * from (values
          ('nexora_set_updated_at()','postgres'),('nexora_set_updated_at()','service_role'),
          ('rls_auto_enable()','postgres'),('rls_auto_enable()','service_role'),
          ('nexora_register_device(uuid,text)','postgres'),('nexora_register_device(uuid,text)','authenticated'),
          ('nexora_sync_push(uuid,jsonb)','postgres'),('nexora_sync_push(uuid,jsonb)','authenticated'),
          ('nexora_private.register_device(uuid,text)','postgres'),('nexora_private.register_device(uuid,text)','authenticated'),
          ('nexora_private.push(uuid,jsonb)','postgres'),('nexora_private.push(uuid,jsonb)','authenticated'),
          ('nexora_private.apply_operation(uuid,uuid,jsonb)','postgres'),('nexora_private.apply_core(uuid,uuid,uuid,text,uuid,text,jsonb,text)','postgres'),
          ('nexora_private.sync_user()','postgres'),('nexora_private.patch_spec(text,boolean)','postgres'),('nexora_private.check_parent(uuid,uuid,uuid,uuid)','postgres'),
          ('nexora_private.guard_row()','postgres'),('nexora_private.guard_task_cycle()','postgres'),('nexora_private.guard_sync_log()','postgres'),
          ('nexora_private.guard_device()','postgres'),('nexora_private.lock_user(uuid)','postgres'),('nexora_private.user_lock_key(uuid)','postgres'),
          -- S3
          ('nexora_resolve_conflict(uuid,uuid,uuid,text,jsonb)','postgres'),('nexora_resolve_conflict(uuid,uuid,uuid,text,jsonb)','authenticated'),
          ('nexora_revoke_device(uuid,uuid)','postgres'),('nexora_revoke_device(uuid,uuid)','authenticated'),
          ('nexora_private.resolve_conflict(uuid,uuid,uuid,text,jsonb)','postgres'),('nexora_private.resolve_conflict(uuid,uuid,uuid,text,jsonb)','authenticated'),
          ('nexora_private.revoke_device(uuid,uuid)','postgres'),('nexora_private.revoke_device(uuid,uuid)','authenticated'),
          ('nexora_private.resolve_core(uuid,uuid,uuid,sync_conflicts,text,jsonb,text)','postgres'),
          -- S4
          ('nexora_sync_pull(uuid,bigint,integer)','postgres'),('nexora_sync_pull(uuid,bigint,integer)','authenticated'),
          ('nexora_private.pull(uuid,bigint,integer)','postgres'),('nexora_private.pull(uuid,bigint,integer)','authenticated'),
          ('nexora_private.guard_conflict_seq()','postgres'),
          ('nexora_private.throttle(uuid,text,integer)','postgres'),
          -- due time (20261116100000): a pure helper for the date/time pairing rule, owner-only like the other private helpers
          ('nexora_private.pair_due_time(jsonb,jsonb)','postgres')) v(fn, g))));
  perform pg_temp.assert('every_expected_execute_grant_exists',
    (select count(*) from pg_proc p, lateral aclexplode(p.proacl) a2
      where p.pronamespace in ('public'::regnamespace,'nexora_private'::regnamespace) and a2.privilege_type='EXECUTE'
        and a2.grantee = 'authenticated'::regrole) = 10);
  perform pg_temp.assert('no_function_has_a_null_acl',
    not exists (select 1 from pg_proc where pronamespace in ('public'::regnamespace,'nexora_private'::regnamespace) and proacl is null));
  perform pg_temp.assert('schema_usage_only_for_authenticated',
    has_schema_privilege('authenticated','nexora_private','usage') and not has_schema_privilege('anon','nexora_private','usage')
    and not has_schema_privilege('service_role','nexora_private','usage'));
  perform pg_temp.assert('no_new_public_definer_functions',
    (select array_agg(proname::text order by proname) from pg_proc where pronamespace='public'::regnamespace and prosecdef) = array['rls_auto_enable']);
  perform pg_temp.assert('public_function_set_is_exactly_the_reviewed_seven',
    (select array_agg(proname::text order by proname) from pg_proc where pronamespace='public'::regnamespace)
      = array['nexora_register_device','nexora_resolve_conflict','nexora_revoke_device','nexora_set_updated_at','nexora_sync_pull','nexora_sync_push','rls_auto_enable']);
  -- S9 final state: no client write privilege on the synchronized tables (the pre-S9 state is asserted by s2_pre_s9_grants_test.sql)
  perform pg_temp.assert('direct_table_grants_after_s9',
    (select string_agg(table_name || ':' || privilege_type, ',' order by table_name, privilege_type)
       from information_schema.role_table_grants where table_schema='public' and grantee='authenticated')
    = 'devices:SELECT,profiles:INSERT,profiles:SELECT,profiles:UPDATE,projects:SELECT,sync_conflicts:SELECT,sync_operations:SELECT,tasks:SELECT');
  perform pg_temp.assert('no_client_write_privilege_on_synchronized_tables',
    not exists (select 1 from information_schema.role_table_grants
                 where table_schema='public' and table_name in ('projects','tasks','project_members')
                   and grantee in ('authenticated','anon','PUBLIC') and privilege_type <> 'SELECT'));
  perform pg_temp.assert('rate_limit_tables_have_no_client_privileges',
    not exists (select 1 from information_schema.role_table_grants where table_schema='nexora_private' and grantee in ('authenticated','anon','PUBLIC','service_role'))
    and (select count(*) from pg_class where relnamespace='nexora_private'::regnamespace and relkind='r' and not relrowsecurity) = 0);
  perform pg_temp.assert('anon_has_no_table_grants',
    not exists (select 1 from information_schema.role_table_grants where table_schema='public' and grantee='anon'));
  perform pg_temp.assert('rls_still_enabled_everywhere',
    not exists (select 1 from pg_class where relnamespace='public'::regnamespace and relkind='r' and not relrowsecurity));
end $$;
select count(*) as passed from _r;
rollback;
