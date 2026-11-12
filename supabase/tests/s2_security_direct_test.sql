-- S2 security hardening suite (Phase 3 consolidation, workstream 2). Rollback-only.
-- Direct calls to nexora_private entry points as `authenticated`, internal-function denial, bypass resistance,
-- search_path shadowing, schema/sequence/table privileges.
begin;
\ir s2_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1); gone uuid := pg_temp.u('99999999', 1);
  anon_u uuid := pg_temp.u('aa000000', 1);
  da uuid := pg_temp.u('d0000000', 1); db uuid := pg_temp.u('d0000000', 2);
  pa uuid := pg_temp.u('e1000000', 1); pb uuid := pg_temp.u('e1000000', 2);
  r jsonb; r2 jsonb; ops jsonb; fn text; n int; shadow_rows int;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  insert into auth.users(id, is_anonymous) values (anon_u, true);
  perform pg_temp.reg(a, da); perform pg_temp.reg(b, db);
  insert into public.projects(id, owner_id, name) values (pb, b, 'Bs private project');

  ---------------------------------------------------------------- direct call to the private entry points (bypassing the INVOKER wrappers)
  ops := jsonb_build_array(pg_temp.op(pg_temp.nid(), 'project', pa, 'create', null, '{"name":"Direct"}'));
  r := pg_temp.rpc(a, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text));
  perform pg_temp.assert('direct_push_with_valid_jwt_works_and_is_owner_scoped',
    r -> 'results' -> 0 ->> 'status' = 'applied' and (select owner_id from public.projects where id = pa) = a);
  r := pg_temp.rpc(null, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text), false, 'authenticated');
  perform pg_temp.assert('direct_push_without_uid_is_unauthenticated', pg_temp.err(r) = '28000' and pg_temp.msg(r) = 'unauthenticated');
  r := pg_temp.rpc(anon_u, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text), true);
  perform pg_temp.assert('direct_push_anonymous_claim_rejected', pg_temp.err(r) = '42501' and pg_temp.msg(r) = 'anonymous_not_allowed');
  r := pg_temp.rpc(anon_u, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text), false);
  perform pg_temp.assert('direct_push_anonymous_flag_in_auth_users_rejected', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(gone, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text));
  perform pg_temp.assert('direct_push_deleted_user_rejected', pg_temp.err(r) = '28000');
  r := pg_temp.rpc(b, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text));
  perform pg_temp.assert('direct_push_with_foreign_device_is_device_invalid', pg_temp.err(r) = 'NX001');
  perform pg_temp.assert('direct_push_foreign_device_wrote_nothing', (select count(*) from public.sync_operations where user_id = b) = 0);
  r := pg_temp.rpc(null, format('select nexora_private.register_device(%L, null)', pg_temp.u('d0000000', 9)), false, 'anon');
  perform pg_temp.assert('direct_register_as_anon_role_denied', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(null, format('select nexora_private.push(%L, %L::jsonb)', da, ops::text), false, 'anon');
  perform pg_temp.assert('direct_push_as_anon_role_denied', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(null, format('select public.nexora_sync_push(%L, %L::jsonb)', da, ops::text), false, 'anon');
  perform pg_temp.assert('wrapper_as_anon_role_denied', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(null, format('select public.nexora_sync_push(%L, %L::jsonb)', da, ops::text), false, 'service_role');
  perform pg_temp.assert('wrapper_as_service_role_denied', pg_temp.err(r) = '42501');

  ---------------------------------------------------------------- internal functions are not callable by any client role
  foreach fn in array array[
    format('nexora_private.apply_operation(%L, %L, ''{}''::jsonb)', a, da),
    format('nexora_private.apply_core(%L, %L, %L, ''project'', %L, ''create'', ''{}''::jsonb, ''h'')', b, da, pg_temp.nid(), pb),
    'nexora_private.sync_user()', 'nexora_private.patch_spec(''project'', true)',
    format('nexora_private.check_parent(%L, %L, %L, %L)', a, pa, pa, pa),
    format('nexora_private.lock_user(%L)', a), format('nexora_private.user_lock_key(%L)', a)] loop
    r := pg_temp.rpc(a, format('select to_jsonb(%s)', fn));
    perform pg_temp.assert('internal_denied_authenticated: ' || split_part(fn, '(', 1), pg_temp.err(r) = '42501');
    r := pg_temp.rpc(null, format('select to_jsonb(%s)', fn), false, 'anon');
    perform pg_temp.assert('internal_denied_anon: ' || split_part(fn, '(', 1), pg_temp.err(r) = '42501');
  end loop;
  -- the spoofed-owner call (apply_operation with another user's id) never ran
  perform pg_temp.assert('spoofed_owner_direct_call_changed_nothing', (select name from public.projects where id = pb) = 'Bs private project'
     and (select count(*) from public.sync_operations where user_id = b) = 0);

  ---------------------------------------------------------------- privileges on schema, sequence, history table
  r := pg_temp.rpc(a, 'create function nexora_private.evil() returns int language sql as $f$ select 1 $f$');
  perform pg_temp.assert('authenticated_cannot_create_in_nexora_private', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'select to_jsonb(nextval(''nexora_private.change_seq''))');
  perform pg_temp.assert('authenticated_cannot_use_change_seq', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'create table nexora_private.t(x int)');
  perform pg_temp.assert('authenticated_cannot_create_table_in_nexora_private', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'create table public.evil(x int)');
  perform pg_temp.assert('authenticated_cannot_create_table_in_public', pg_temp.err(r) = '42501');
  -- history is append-only and not client-writable
  r := pg_temp.rpc(a, format('with x as (update public.sync_operations set status = ''applied'' where user_id = %L returning 1) select to_jsonb(count(*)) from x', a));
  perform pg_temp.assert('history_update_denied_or_empty', pg_temp.err(r) is not null or (r #>> '{}')::int = 0);
  r := pg_temp.rpc(a, format('with x as (delete from public.sync_operations where user_id = %L returning 1) select to_jsonb(count(*)) from x', a));
  perform pg_temp.assert('history_delete_denied_or_empty', pg_temp.err(r) is not null or (r #>> '{}')::int = 0);
  r := pg_temp.rpc(a, format('with x as (insert into public.sync_operations(user_id, operation_id, device_id, entity_type, entity_id, op_type, request_hash, status, result, server_seq) '
                              'values (%L, %L, %L, ''project'', %L, ''create'', ''h'', ''applied'', ''{}''::jsonb, 1) returning 1) select to_jsonb(count(*)) from x',
                              a, pg_temp.nid(), da, pg_temp.u('e1000000', 77)));
  perform pg_temp.assert('client_cannot_forge_history_row', pg_temp.err(r) is not null);
  -- RLS: each user reads only own history and conflicts
  r := pg_temp.rpc(b, 'select to_jsonb(count(*)) from public.sync_operations');
  perform pg_temp.assert('cross_user_history_invisible', (r #>> '{}')::int = 0);
  r := pg_temp.rpc(a, 'select to_jsonb(count(*)) from public.sync_operations');
  perform pg_temp.assert('own_history_visible', (r #>> '{}')::int >= 1);

  ---------------------------------------------------------------- search_path shadowing
  create temp table sync_operations (like public.sync_operations);
  grant all on pg_temp.sync_operations to public;
  perform set_config('search_path', 'pg_temp, public', true);   -- applies to the rpc statement too (role switch keeps session GUCs)
  r := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'project', pg_temp.u('e1000000', 5), 'create', null, '{"name":"Shadow"}')));
  perform set_config('search_path', '"$user", public', true);
  perform pg_temp.assert('shadow_push_succeeded', r -> 'results' -> 0 ->> 'status' = 'applied');
  select count(*) into shadow_rows from pg_temp.sync_operations;
  perform pg_temp.assert('search_path_shadow_table_is_not_used', shadow_rows = 0
     and exists (select 1 from public.projects where id = pg_temp.u('e1000000', 5)) and exists (select 1 from public.sync_operations where entity_id = pg_temp.u('e1000000', 5)));

  ---------------------------------------------------------------- injection-shaped input
  r := pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 6), 'create', null, jsonb_build_object('name', 'x', 'name", owner_id = ''x', jsonb_build_object('a', 1)));
  perform pg_temp.assert('quoted_key_is_invalid_patch', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 7), 'create', null, jsonb_build_object('name', 'x''); drop table public.projects; --'));
  perform pg_temp.assert('injection_string_is_stored_as_data', r ->> 'status' = 'applied' and r -> 'row' ->> 'name' like 'x''%'
     and to_regclass('public.projects') is not null);
  r := pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 8), 'create', null, '{"name":"y","owner_id":"00000000-0000-0000-0000-000000000001"}');
  perform pg_temp.assert('owner_id_in_patch_rejected', r ->> 'error_code' = 'invalid_patch');
  -- entity_type is whitelisted before any dynamic SQL
  r := pg_temp.c(a, da, 'projects; drop table public.tasks', pg_temp.u('e1000000', 9), 'create', null, '{"name":"z"}');
  perform pg_temp.assert('entity_type_injection_rejected', r ->> 'error_code' = 'invalid_op' and to_regclass('public.tasks') is not null);

  select count(*) into n from _r;
  raise notice 'assertions=%', n;
end $$;
select 'S2 direct-call security suite: ' || count(*) || ' assertions passed' from _r;
rollback;
