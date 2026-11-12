-- S3 device revocation suite. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1); gone uuid := pg_temp.u('99999999', 1); anon_u uuid := pg_temp.u('aa000000', 1);
  d1 uuid := pg_temp.u('d0000000', 1); d2 uuid := pg_temp.u('d0000000', 2); d3 uuid := pg_temp.u('d0000000', 3); db1 uuid := pg_temp.u('d0000000', 50);
  p uuid := pg_temp.u('e1000000', 1);
  r jsonb; n int; i int; ops jsonb;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  insert into auth.users(id, is_anonymous) values (anon_u, true);
  perform pg_temp.reg(a, d1); perform pg_temp.reg(a, d2); perform pg_temp.reg(a, d3); perform pg_temp.reg(b, db1);
  perform pg_temp.c(a, d1, 'project', p, 'create', null, '{"name":"Rev host"}');
  ops := jsonb_build_array(pg_temp.op(pg_temp.nid(), 'project', p, 'update', 1, '{"name":"after revoke"}'));

  r := pg_temp.revoke(a, d1, d2);
  perform pg_temp.assert('rv_revokes_another_device', r ->> 'revoked' = 'true' and r ->> 'device_id' = d2::text and (r ->> 'active_devices')::int = 2);
  perform pg_temp.assert('rv_row_kept_with_timestamp', (select revoked_at is not null from public.devices where id = d2));
  r := pg_temp.revoke(a, d1, d2);
  perform pg_temp.assert('rv_is_idempotent', r ->> 'revoked' = 'false' and (r ->> 'active_devices')::int = 2);
  perform pg_temp.assert('rv_revoked_device_cannot_push', pg_temp.err(pg_temp.push(a, d2, ops)) = 'NX001');
  perform pg_temp.assert('rv_revoked_device_cannot_pull', pg_temp.err(pg_temp.pull(a, d2, 0)) = 'NX001');
  perform pg_temp.assert('rv_revoked_device_cannot_register_again', pg_temp.err(pg_temp.reg(a, d2)) = 'NX001');
  perform pg_temp.assert('rv_revoked_device_cannot_revoke', pg_temp.err(pg_temp.revoke(a, d2, d3)) = 'NX001');
  perform pg_temp.assert('rv_revoked_device_cannot_resolve', pg_temp.err(pg_temp.resolve(a, d2, pg_temp.nid(), pg_temp.u('c1000000', 1), 'resolved_server')) = 'NX001');
  perform pg_temp.assert('rv_other_devices_still_work', pg_temp.push(a, d1, ops) -> 'results' -> 0 ->> 'status' = 'applied');
  perform pg_temp.assert('rv_history_of_revoked_device_kept', exists (select 1 from public.devices where id = d2 and user_id = a));

  perform pg_temp.assert('rv_foreign_device_target_refused', pg_temp.err(pg_temp.revoke(a, d1, db1)) = 'NX001' and (select revoked_at is null from public.devices where id = db1));
  perform pg_temp.assert('rv_unknown_target_refused_with_same_error', pg_temp.err(pg_temp.revoke(a, d1, pg_temp.u('d0000000', 99))) = 'NX001');
  perform pg_temp.assert('rv_other_user_cannot_revoke_my_device', pg_temp.err(pg_temp.revoke(b, db1, d1)) = 'NX001' and (select revoked_at is null from public.devices where id = d1));
  perform pg_temp.assert('rv_caller_must_be_my_active_device', pg_temp.err(pg_temp.revoke(a, db1, d1)) = 'NX001' and pg_temp.err(pg_temp.revoke(a, pg_temp.u('d0000000', 98), d1)) = 'NX001');
  perform pg_temp.assert('rv_null_arguments', pg_temp.err(pg_temp.revoke(a, d1, null)) = 'NX005');

  perform pg_temp.assert('rv_signed_out', pg_temp.err(pg_temp.revoke(null, d1, d3)) = '28000');
  perform pg_temp.assert('rv_anonymous_claim', pg_temp.err(pg_temp.revoke(anon_u, d1, d3, true)) = '42501');
  perform pg_temp.assert('rv_deleted_user', pg_temp.err(pg_temp.revoke(gone, d1, d3)) = '28000');
  perform pg_temp.assert('rv_private_entry_point_same_checks', pg_temp.err(pg_temp.rpc(null, format('select nexora_private.revoke_device(%L, %L)', d1, d3))) = '28000');
  perform pg_temp.assert('rv_anon_role_has_no_execute', pg_temp.err(pg_temp.rpc(null, format('select public.nexora_revoke_device(%L, %L)', d1, d3), false, 'anon')) = '42501');
  perform pg_temp.assert('rv_service_role_has_no_execute', pg_temp.err(pg_temp.rpc(null, format('select public.nexora_revoke_device(%L, %L)', d1, d3), false, 'service_role')) = '42501');
  perform pg_temp.assert('rv_clients_cannot_unrevoke_or_edit_devices',
    pg_temp.err(pg_temp.rpc(a, format('with x as (update public.devices set revoked_at = null where id = %L returning 1) select to_jsonb(count(*)) from x', d2))) is not null
    or (select revoked_at is not null from public.devices where id = d2));

  -- a revoked device frees a slot of the ten-device cap
  for i in 4 .. 10 loop perform pg_temp.reg(a, pg_temp.u('d0000000', i)); end loop;     -- d1, d3, d4..d10 active = 9
  perform pg_temp.assert('rv_cap_setup', (select count(*) from public.devices where user_id = a and revoked_at is null) = 9);
  perform pg_temp.assert('rv_tenth_device_registers', pg_temp.reg(a, pg_temp.u('d0000000', 11)) ->> 'created' = 'true');
  perform pg_temp.assert('rv_eleventh_is_refused', pg_temp.err(pg_temp.reg(a, pg_temp.u('d0000000', 12))) = 'NX002');
  r := pg_temp.revoke(a, d1, pg_temp.u('d0000000', 4));
  perform pg_temp.assert('rv_revoking_frees_a_slot', (r ->> 'active_devices')::int = 9 and pg_temp.reg(a, pg_temp.u('d0000000', 12)) ->> 'created' = 'true');

  -- a device may revoke itself (sign-out); afterwards it is refused everywhere
  r := pg_temp.revoke(a, d3, d3);
  perform pg_temp.assert('rv_self_revocation', r ->> 'revoked' = 'true' and pg_temp.err(pg_temp.push(a, d3, ops)) = 'NX001' and pg_temp.err(pg_temp.pull(a, d3, 0)) = 'NX001');

  -- shape and grants
  perform pg_temp.assert('rv_wrapper_invoker_private_definer', (select not prosecdef and proconfig = array['search_path=""'] from pg_proc where pronamespace = 'public'::regnamespace and proname = 'nexora_revoke_device')
     and (select prosecdef and proconfig @> array['search_path=""','lock_timeout=5s'] from pg_proc where pronamespace = 'nexora_private'::regnamespace and proname = 'revoke_device'));
  select count(*) into n from _r;
  raise notice 'assertions=%', n;
end $$;
select 'S3 revoke suite: ' || count(*) || ' assertions passed' from _r;
rollback;
