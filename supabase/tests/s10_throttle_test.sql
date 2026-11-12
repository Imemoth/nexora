-- S10a throttle suite: per-user per-minute counters, NX007 rate_limited. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1); c uuid := pg_temp.u('cccccccc', 1);
  da uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2); db uuid := pg_temp.u('d0000000', 3); dc uuid := pg_temp.u('d0000000', 4);
  p uuid := pg_temp.u('e1000000', 1);
  r jsonb; i int; ok int; refused int; before_ops int; bucket_time timestamptz; n_old int; opsarr jsonb;
begin
  -- never straddle a minute boundary inside the suite
  if extract(second from clock_timestamp()) > 52 then perform pg_sleep(9); end if;
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b); perform pg_temp.mkuser(c);

  perform pg_temp.assert('th_policy_defaults',
    (select pull_calls_per_minute = 120 and write_calls_per_minute = 120 and write_ops_per_minute = 6000 from nexora_private.rate_policy)
    and (select count(*) = 1 from nexora_private.rate_policy));
  begin insert into nexora_private.rate_policy(singleton) values (false); perform pg_temp.assert('th_policy_is_one_row', false);
  exception when check_violation or unique_violation then perform pg_temp.assert('th_policy_is_one_row', true); end;
  begin update nexora_private.rate_policy set write_calls_per_minute = 0; perform pg_temp.assert('th_policy_rejects_nonpositive_limits', false);
  exception when check_violation then perform pg_temp.assert('th_policy_rejects_nonpositive_limits', true); end;

  update nexora_private.rate_policy set pull_calls_per_minute = 3, write_calls_per_minute = 3, write_ops_per_minute = 10;

  ---------------------------------------------------------------- pull kind: exactly the limit succeeds, the next is refused
  perform pg_temp.reg(a, da);                       -- write call 1 of 3 (a)
  ok := 0; refused := 0;
  for i in 1 .. 6 loop
    r := pg_temp.pull(a, da, 0);
    if r ? 'error' then
      refused := refused + 1;
      perform pg_temp.assert('th_refusal_is_nx007_rate_limited_' || i, pg_temp.err(r) = 'NX007' and pg_temp.msg(r) = 'rate_limited');
    else ok := ok + 1; end if;
  end loop;
  perform pg_temp.assert('th_exactly_the_limit_of_pulls_succeed', ok = 3 and refused = 3);
  perform pg_temp.assert('th_failed_calls_do_not_inflate_the_counter',
    (select calls from nexora_private.rate_bucket where user_id = a and kind = 'pull') = 3);

  ---------------------------------------------------------------- kinds are independent: writes still allowed after the pull limit
  r := pg_temp.reg(a, da2);                         -- write call 2 of 3
  perform pg_temp.assert('th_write_kind_independent_of_pull_kind', not (r ? 'error'));

  ---------------------------------------------------------------- other users are unaffected
  perform pg_temp.reg(b, db);
  r := pg_temp.pull(b, db, 0);
  perform pg_temp.assert('th_other_user_unaffected', not (r ? 'error'));
  perform pg_temp.assert('th_buckets_are_per_user', (select count(distinct user_id) from nexora_private.rate_bucket) = 2);

  ---------------------------------------------------------------- write calls: third ok, fourth refused and nothing recorded
  r := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.u('c0000000', 1), 'project', p, 'create', null, '{"name":"P"}')));  -- write call 3 of 3
  perform pg_temp.assert('th_last_allowed_write_succeeds', r -> 'results' -> 0 ->> 'status' = 'applied');
  r := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.u('c0000000', 2), 'project', pg_temp.u('e1000000', 2), 'create', null, '{"name":"Q"}')));
  perform pg_temp.assert('th_fourth_write_refused_nx007', pg_temp.err(r) = 'NX007' and pg_temp.msg(r) = 'rate_limited');
  perform pg_temp.assert('th_refused_write_recorded_nothing',
    not exists (select 1 from public.sync_operations where operation_id = pg_temp.u('c0000000', 2))
    and not exists (select 1 from public.projects where id = pg_temp.u('e1000000', 2)));
  r := pg_temp.revoke(a, da, da2);
  perform pg_temp.assert('th_revoke_and_resolve_count_as_writes', pg_temp.err(r) = 'NX007');
  r := pg_temp.resolve(a, da, pg_temp.u('c0000000', 3), pg_temp.u('f0000000', 1), 'resolved_server');
  perform pg_temp.assert('th_resolve_is_throttled_before_any_lookup', pg_temp.err(r) = 'NX007');
  r := pg_temp.reg(a, pg_temp.u('d0000000', 9));
  perform pg_temp.assert('th_register_is_throttled', pg_temp.err(r) = 'NX007');

  ---------------------------------------------------------------- failed requests roll back their own increment (only successful calls consume budget)
  r := pg_temp.pull(b, db, 0, 0);                   -- invalid limit: NX005, increment rolled back with the call
  perform pg_temp.assert('th_invalid_request_is_still_nx005', pg_temp.err(r) = 'NX005');
  r := pg_temp.pull(b, db, 0);                      -- b pull call 2 of 3
  r := pg_temp.pull(b, db, 0);                      -- call 3 of 3
  perform pg_temp.assert('th_failed_requests_consumed_no_budget', not (r ? 'error'));
  r := pg_temp.pull(b, db, 0);
  perform pg_temp.assert('th_fourth_successful_pull_refused', pg_temp.err(r) = 'NX007');

  ---------------------------------------------------------------- operation budget: 10 per minute, a push is weighed by its operations
  update nexora_private.rate_policy set write_calls_per_minute = 100;
  perform pg_temp.reg(c, dc);
  opsarr := '[]'::jsonb;
  for i in 1 .. 11 loop opsarr := opsarr || jsonb_build_array(pg_temp.op(pg_temp.u('c1000000', i), 'project', pg_temp.u('e3000000', i), 'create', null, '{"name":"X"}')); end loop;
  r := pg_temp.push(c, dc, opsarr);
  perform pg_temp.assert('th_eleven_operations_exceed_the_ten_operation_budget', pg_temp.err(r) = 'NX007');
  perform pg_temp.assert('th_over_budget_push_applied_nothing', not exists (select 1 from public.projects where owner_id = c));
  opsarr := '[]'::jsonb;
  for i in 1 .. 6 loop opsarr := opsarr || jsonb_build_array(pg_temp.op(pg_temp.u('c2000000', i), 'project', pg_temp.u('e4000000', i), 'create', null, '{"name":"X"}')); end loop;
  r := pg_temp.push(c, dc, opsarr);
  perform pg_temp.assert('th_six_operations_fit', not (r ? 'error') and jsonb_array_length(r -> 'results') = 6);
  r := pg_temp.push(c, dc, opsarr);                    -- replay of the same six: still weighs six, 12 > 10
  perform pg_temp.assert('th_replays_are_weighed_like_new_work', pg_temp.err(r) = 'NX007');
  perform pg_temp.assert('th_ops_counter_is_exact', (select b3.ops from nexora_private.rate_bucket b3 where b3.user_id = c and b3.kind = 'write') = 6);

  ---------------------------------------------------------------- batch-size validation runs before the throttle (no budget consumed)
  opsarr := '[]'::jsonb;
  for i in 1 .. 101 loop opsarr := opsarr || jsonb_build_array('{}'::jsonb); end loop;
  select b2.ops into before_ops from nexora_private.rate_bucket b2 where b2.user_id = c and b2.kind = 'write';
  r := pg_temp.push(c, dc, opsarr);
  perform pg_temp.assert('th_oversized_batch_is_nx003_not_throttled', pg_temp.err(r) = 'NX003'
    and (select b3.ops from nexora_private.rate_bucket b3 where b3.user_id = c and b3.kind = 'write') = before_ops);

  ---------------------------------------------------------------- window rollover and lazy pruning
  insert into nexora_private.rate_bucket(user_id, bucket, kind, calls, ops)
    values (a, date_trunc('minute', clock_timestamp()) - interval '1 minute', 'write', 3, 10);
  insert into nexora_private.rate_bucket(user_id, bucket, kind, calls, ops)
    select a, date_trunc('minute', clock_timestamp()) - interval '1 hour' - (g || ' minutes')::interval, 'write', 1, 1 from generate_series(1, 30) g;
  select count(*) into n_old from nexora_private.rate_bucket where user_id = a and bucket < date_trunc('minute', clock_timestamp()) - interval '10 minutes';
  update nexora_private.rate_policy set write_calls_per_minute = 5, pull_calls_per_minute = 100;
  r := pg_temp.pull(a, da, 0);                      -- any call of a prunes at most 20 old rows
  perform pg_temp.assert('th_previous_minute_bucket_does_not_count_now', not (r ? 'error'));
  perform pg_temp.assert('th_old_buckets_pruned_in_bounded_steps',
    n_old = 30 and (select count(*) from nexora_private.rate_bucket where user_id = a and bucket < date_trunc('minute', clock_timestamp()) - interval '10 minutes') = 10);
  perform pg_temp.assert('th_other_users_buckets_untouched_by_pruning', (select count(*) from nexora_private.rate_bucket where user_id = b) >= 1);

  ---------------------------------------------------------------- unauthenticated and anonymous callers consume nothing
  r := pg_temp.pull(null, da, 0);
  perform pg_temp.assert('th_unauthenticated_is_28000_before_the_throttle', pg_temp.err(r) = '28000');
  perform pg_temp.assert('th_no_bucket_without_a_user', not exists (select 1 from nexora_private.rate_bucket where user_id is null));

  ---------------------------------------------------------------- the counters are not reachable by clients
  r := pg_temp.rpc(a, 'select to_jsonb(count(*)) from nexora_private.rate_bucket');
  perform pg_temp.assert('th_authenticated_cannot_read_buckets', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'select to_jsonb(count(*)) from nexora_private.rate_policy');
  perform pg_temp.assert('th_authenticated_cannot_read_policy', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'select to_jsonb(nexora_private.throttle(gen_random_uuid(), ''write'', 1))');
  perform pg_temp.assert('th_authenticated_cannot_call_throttle', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(a, 'update nexora_private.rate_policy set write_calls_per_minute = 1000000 returning to_jsonb(1)');
  perform pg_temp.assert('th_authenticated_cannot_raise_its_own_limit', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(null, 'select to_jsonb(count(*)) from nexora_private.rate_bucket', false, 'anon');
  perform pg_temp.assert('th_anon_cannot_read_buckets', pg_temp.err(r) = '42501');
  r := pg_temp.rpc(null, 'select to_jsonb(count(*)) from nexora_private.rate_bucket', false, 'service_role');
  perform pg_temp.assert('th_service_role_has_no_bucket_access', pg_temp.err(r) = '42501');
  perform pg_temp.assert('th_throttle_is_definer_with_empty_search_path',
    (select prosecdef and proconfig @> array['search_path=""'] and pg_get_userbyid(proowner) = 'postgres'
       from pg_proc where oid = 'nexora_private.throttle(uuid,text,integer)'::regprocedure));
  perform pg_temp.assert('th_all_five_entry_points_call_the_throttle',
    (select count(*) = 5 from pg_proc where pronamespace = 'nexora_private'::regnamespace
        and proname in ('register_device','push','pull','resolve_conflict','revoke_device') and prosrc like '%nexora_private.throttle(%'));

  ---------------------------------------------------------------- deleting a user removes its counters
  delete from auth.users where id = b;
  perform pg_temp.assert('th_user_delete_cascades_buckets', not exists (select 1 from nexora_private.rate_bucket where user_id = b));
end $$;
select count(*) as passed from _r;
rollback;
