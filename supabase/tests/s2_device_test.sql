-- S2 device registration suite. Rollback-only.
begin;
\ir s2_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da uuid := pg_temp.u('d0000000', 1); r jsonb; i int; dev uuid;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);

  r := pg_temp.reg(a, da, 'Laptop');
  perform pg_temp.assert('register_creates_device', r = jsonb_build_object('device_id', da, 'created', true, 'active_devices', 1));
  perform pg_temp.assert('owner_comes_from_the_token', (select user_id from public.devices where id = da) = a);
  perform pg_temp.assert('label_stored', (select label from public.devices where id = da) = 'Laptop');
  r := pg_temp.reg(a, da, 'Renamed');
  perform pg_temp.assert('register_is_idempotent', r = jsonb_build_object('device_id', da, 'created', false, 'active_devices', 1));
  perform pg_temp.assert('label_not_overwritten_by_re_register', (select label from public.devices where id = da) = 'Laptop');
  perform pg_temp.assert('last_seen_at_set', (select last_seen_at from public.devices where id = da) is not null);

  -- cross-user
  r := pg_temp.reg(b, da);
  perform pg_temp.assert('register_other_users_device_id_rejected', pg_temp.err(r) = 'NX001' and pg_temp.msg(r) = 'device_invalid');
  perform pg_temp.assert('other_users_device_not_taken_over', (select user_id from public.devices where id = da) = a);

  -- input validation
  r := pg_temp.rpc(a, 'select public.nexora_register_device(null, null)');
  perform pg_temp.assert('null_device_id_rejected', pg_temp.err(r) = 'NX005' and pg_temp.msg(r) = 'invalid_request');
  r := pg_temp.reg(a, pg_temp.u('d0000000', 50), repeat('x', 101));
  perform pg_temp.assert('label_length_enforced', pg_temp.err(r) = 'NX005');
  perform pg_temp.assert('invalid_label_registered_nothing', not exists (select 1 from public.devices where id = pg_temp.u('d0000000', 50)));
  r := pg_temp.reg(a, pg_temp.u('d0000000', 51), repeat('x', 100));
  perform pg_temp.assert('label_of_100_accepted', r ->> 'created' = 'true');

  -- revocation
  update public.devices set revoked_at = now() where id = da;
  r := pg_temp.reg(a, da);
  perform pg_temp.assert('revoked_device_cannot_re_register', pg_temp.err(r) = 'NX001');
  r := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.u('c0000000', 1), 'project', pg_temp.u('e0000000', 1), 'create', null, '{"name":"P"}')));
  perform pg_temp.assert('revoked_device_rejected', pg_temp.err(r) = 'NX001' and pg_temp.msg(r) = 'device_invalid');
  perform pg_temp.assert('revoked_device_push_recorded_nothing',
    not exists (select 1 from public.sync_operations where user_id = a) and not exists (select 1 from public.projects where owner_id = a));
  perform pg_temp.assert('revoked_device_cannot_be_unrevoked_through_register', (select revoked_at from public.devices where id = da) is not null);

  -- device cap (10 active); the revoked device does not count
  for i in 2..10 loop dev := pg_temp.u('d0000000', 100 + i); perform pg_temp.reg(b, dev); end loop;
  perform pg_temp.assert('nine_active_devices_so_far', (select count(*) from public.devices where user_id = b and revoked_at is null) = 9);
  r := pg_temp.reg(b, pg_temp.u('d0000000', 120));
  perform pg_temp.assert('tenth_device_accepted', r ->> 'active_devices' = '10');
  r := pg_temp.reg(b, pg_temp.u('d0000000', 121));
  perform pg_temp.assert('device_limit_enforced_via_wrapper', pg_temp.err(r) = 'NX002' and pg_temp.msg(r) = 'device_limit');
  perform pg_temp.assert('rejected_registration_left_no_device', not exists (select 1 from public.devices where id = pg_temp.u('d0000000', 121)));
  update public.devices set revoked_at = now() where id = pg_temp.u('d0000000', 102);
  r := pg_temp.reg(b, pg_temp.u('d0000000', 121));
  perform pg_temp.assert('revoking_frees_a_slot', r ->> 'created' = 'true' and r ->> 'active_devices' = '10');
  perform pg_temp.assert('registered_device_can_push', (pg_temp.one(b, pg_temp.u('d0000000', 121),
     pg_temp.op(pg_temp.u('c0000000', 2), 'project', pg_temp.u('e0000000', 2), 'create', null, '{"name":"B"}'))) ->> 'status' = 'applied');
  perform pg_temp.assert('registration_takes_the_user_lock', pg_temp.holds_user_lock(a) and pg_temp.holds_user_lock(b));
end $$;
select count(*) as passed from _r;
rollback;
