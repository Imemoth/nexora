-- S2 push suite: idempotency, replay, batches, limits, failure injection. Rollback-only.
begin;
\ir s2_helpers.sql
create function public._s2_boom() returns trigger language plpgsql as $$
begin
  if new.title = 'boom-transient' then raise exception 'injected' using errcode = '40001'; end if;
  if new.title = 'boom-integrity' then raise exception 'injected' using errcode = '23514'; end if;
  if new.title = 'boom-bug' then raise exception 'injected bug' using errcode = 'P0001'; end if;
  return new;
end $$;
create trigger s2_boom before insert on public.tasks for each row execute function public._s2_boom();
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da1 uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2); db1 uuid := pg_temp.u('d0000000', 3);
  p uuid := pg_temp.u('e1000000', 1); t uuid := pg_temp.u('e2000000', 1);
  o1 jsonb; o2 jsonb; o3 jsonb; r jsonb; r2 jsonb; first_r jsonb; ops jsonb; i int; n0 int; v0 bigint; opid uuid;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  perform pg_temp.reg(a, da1); perform pg_temp.reg(a, da2); perform pg_temp.reg(b, db1);

  ---------------------------------------------------------------- first application, exact replay, lost response
  opid := pg_temp.u('c1000000', 1);
  o1 := pg_temp.op(opid, 'project', p, 'create', null, '{"name":"Proj"}');
  first_r := pg_temp.one(a, da1, o1);
  perform pg_temp.assert('first_application', first_r ->> 'status' = 'applied' and first_r ->> 'replayed' = 'false');
  perform pg_temp.assert('result_row_is_authoritative_after_commit', (first_r -> 'row' ->> 'change_seq')::bigint = (select change_seq from public.projects where id = p));
  n0 := (select count(*) from public.sync_operations where user_id = a);
  v0 := (select change_seq from public.projects where id = p);
  r := pg_temp.one(a, da1, o1);   -- the client lost the response and retries the identical payload
  perform pg_temp.assert('lost_response_retry_returns_stored_result', r = (first_r || '{"replayed": true}'::jsonb));
  perform pg_temp.assert('replay_changed_nothing', (select count(*) from public.sync_operations where user_id = a) = n0
     and (select change_seq from public.projects where id = p) = v0 and (select version from public.projects where id = p) = 1);
  r := pg_temp.one(a, da2, o1);   -- retried through another device of the same user
  perform pg_temp.assert('replay_from_second_device_of_same_user', r ->> 'replayed' = 'true' and (r ->> 'applied_version')::int = 1);
  perform pg_temp.assert('stored_result_equals_first_response', (select result from public.sync_operations where user_id = a and operation_id = opid) = first_r);
  perform pg_temp.assert('result_row_written_once', (select count(*) from public.sync_operations where user_id = a and operation_id = opid) = 1);

  ---------------------------------------------------------------- same operation_id, different payload
  r := pg_temp.one(a, da1, pg_temp.op(opid, 'project', p, 'create', null, '{"name":"Different"}'));
  perform pg_temp.assert('same_operation_id_different_payload_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'operation_id_reuse');
  perform pg_temp.assert('reuse_rejection_not_recorded_and_original_intact', (select count(*) from public.sync_operations where user_id = a) = n0
     and (select name from public.projects where id = p) = 'Proj');
  r := pg_temp.one(a, da1, pg_temp.op(opid, 'project', pg_temp.u('e1000000', 2), 'create', null, '{"name":"Proj"}'));
  perform pg_temp.assert('same_operation_id_different_entity_rejected', r ->> 'error_code' = 'operation_id_reuse');
  r := pg_temp.one(b, db1, pg_temp.op(opid, 'project', pg_temp.u('e1000000', 3), 'create', null, '{"name":"Bs"}'));
  perform pg_temp.assert('same_operation_id_other_user_is_independent', r ->> 'status' = 'applied' and r ->> 'replayed' = 'false');
  r := pg_temp.one(a, da1, o1);
  perform pg_temp.assert('other_users_use_of_the_id_did_not_affect_replay', r ->> 'replayed' = 'true');

  ---------------------------------------------------------------- rejected operations replay as rejected
  o2 := pg_temp.op(pg_temp.u('c1000000', 2), 'task', t, 'create', null, jsonb_build_object('project_id', p, 'title', 'T', 'owner_id', b));
  r := pg_temp.one(a, da1, o2);
  perform pg_temp.assert('rejected_operation_recorded', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch'
     and exists (select 1 from public.sync_operations where user_id = a and operation_id = pg_temp.u('c1000000', 2) and status = 'rejected' and applied_version is null));
  r2 := pg_temp.one(a, da1, o2);
  perform pg_temp.assert('rejected_operation_replays_as_rejected', r2 = (r || '{"replayed": true}'::jsonb));

  ---------------------------------------------------------------- batches: order, partial replay, isolation of failures
  o3 := pg_temp.op(pg_temp.u('c1000000', 3), 'task', t, 'create', null, jsonb_build_object('project_id', p, 'title', 'Batch task'));
  ops := jsonb_build_array(o1, o3, pg_temp.op(pg_temp.u('c1000000', 4), 'task', pg_temp.u('e2000000', 2), 'create', null, '{"title":"no project"}'),
                           pg_temp.op(pg_temp.u('c1000000', 5), 'project', pg_temp.u('e1000000', 5), 'create', null, '{"name":"After the bad one"}'));
  r := pg_temp.push(a, da1, ops);
  perform pg_temp.assert('results_in_input_order_one_per_operation', jsonb_array_length(r -> 'results') = 4
     and (r -> 'results' -> 0 ->> 'operation_id') = pg_temp.u('c1000000', 1)::text and (r -> 'results' -> 3 ->> 'operation_id') = pg_temp.u('c1000000', 5)::text);
  perform pg_temp.assert('partial_batch_replay_replays_old_and_applies_new', r -> 'results' -> 0 ->> 'replayed' = 'true' and r -> 'results' -> 1 ->> 'status' = 'applied');
  perform pg_temp.assert('one_bad_operation_does_not_block_others', r -> 'results' -> 2 ->> 'status' = 'rejected' and r -> 'results' -> 3 ->> 'status' = 'applied');
  r2 := pg_temp.push(a, da1, ops);
  perform pg_temp.assert('repeated_batch_replays_everything', (select bool_and((x ->> 'replayed')::boolean) from jsonb_array_elements(r2 -> 'results') x));
  perform pg_temp.assert('repeated_batch_created_no_new_rows', (select count(*) from public.sync_operations where user_id = a) = n0 + 4);
  perform pg_temp.assert('no_silent_operation_loss', (select count(*) from public.sync_operations where user_id = a and operation_id in
     (pg_temp.u('c1000000', 1), pg_temp.u('c1000000', 2), pg_temp.u('c1000000', 3), pg_temp.u('c1000000', 4), pg_temp.u('c1000000', 5))) = 5);

  ---------------------------------------------------------------- dependent and duplicated operations inside one batch
  o1 := pg_temp.op(pg_temp.u('c5000000', 1), 'project', pg_temp.u('e1000000', 60), 'create', null, '{"name":"Dependent"}');
  r := pg_temp.push(a, da1, jsonb_build_array(o1,
         pg_temp.op(pg_temp.u('c5000000', 2), 'project', pg_temp.u('e1000000', 60), 'update', 1, '{"name":"Dependent renamed"}'), o1));
  perform pg_temp.assert('create_then_update_in_one_batch', r -> 'results' -> 0 ->> 'status' = 'applied' and r -> 'results' -> 1 ->> 'status' = 'applied'
     and (r -> 'results' -> 1 ->> 'applied_version')::int = 2 and (select name from public.projects where id = pg_temp.u('e1000000', 60)) = 'Dependent renamed');
  perform pg_temp.assert('duplicate_operation_in_one_batch_replays', r -> 'results' -> 2 ->> 'replayed' = 'true' and r -> 'results' -> 2 ->> 'status' = 'applied'
     and (select count(*) from public.sync_operations where user_id = a and operation_id = pg_temp.u('c5000000', 1)) = 1);
  perform pg_temp.assert('replay_returns_the_original_result_not_the_current_state', (r -> 'results' -> 2 -> 'row' ->> 'name') = 'Dependent'
     and (r -> 'results' -> 2 ->> 'applied_version')::int = 1);

  ---------------------------------------------------------------- failed operation leaves no partial mutation
  r := pg_temp.c(a, da1, 'task', t, 'update', 1, '{"title":"good change","status":"bogus"}');
  perform pg_temp.assert('mixed_valid_invalid_patch_rejected', r ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('failed_operation_left_no_partial_change', (select title from public.tasks where id = t) = 'Batch task'
     and (select version from public.tasks where id = t) = 1 and (select field_versions from public.tasks where id = t) = '{}'::jsonb);

  ---------------------------------------------------------------- failure injection
  n0 := (select count(*) from public.sync_operations where user_id = a);
  r := pg_temp.push(a, da1, jsonb_build_array(
        pg_temp.op(pg_temp.nid(), 'project', pg_temp.u('e1000000', 20), 'create', null, '{"name":"before the transient failure"}'),
        pg_temp.op(pg_temp.nid(), 'task', pg_temp.u('e2000000', 20), 'create', null, jsonb_build_object('project_id', p, 'title', 'boom-transient'))));
  perform pg_temp.assert('transient_error_aborts_the_whole_call', pg_temp.err(r) = '40001');
  perform pg_temp.assert('transient_error_records_nothing_and_applies_nothing', (select count(*) from public.sync_operations where user_id = a) = n0
     and not exists (select 1 from public.projects where id = pg_temp.u('e1000000', 20)));
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 21), 'create', null, jsonb_build_object('project_id', p, 'title', 'boom-integrity'));
  perform pg_temp.assert('integrity_violation_is_a_recorded_rejection', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch'
     and exists (select 1 from public.sync_operations where operation_id = (r ->> 'operation_id')::uuid and status = 'rejected')
     and not exists (select 1 from public.tasks where id = pg_temp.u('e2000000', 21)));
  n0 := (select count(*) from public.sync_operations where user_id = a);
  r := pg_temp.push(a, da1, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'task', pg_temp.u('e2000000', 22), 'create', null, jsonb_build_object('project_id', p, 'title', 'boom-bug'))));
  perform pg_temp.assert('unexpected_error_surfaces_and_records_nothing', pg_temp.err(r) = 'P0001' and (select count(*) from public.sync_operations where user_id = a) = n0);

  ---------------------------------------------------------------- limits and malformed input
  r := pg_temp.rpc(a, format('select public.nexora_sync_push(%L, ''[]''::jsonb)', da1));
  perform pg_temp.assert('empty_batch_rejected', pg_temp.err(r) = 'NX005');
  r := pg_temp.rpc(a, format('select public.nexora_sync_push(%L, ''{"a":1}''::jsonb)', da1));
  perform pg_temp.assert('non_array_batch_rejected', pg_temp.err(r) = 'NX005');
  r := pg_temp.rpc(a, format('select public.nexora_sync_push(%L, null)', da1));
  perform pg_temp.assert('null_batch_rejected', pg_temp.err(r) = 'NX005');
  select jsonb_agg(pg_temp.op(pg_temp.u('c2000000', g), 'project', pg_temp.u('e3000000', g), 'create', null, jsonb_build_object('name', 'P' || g))) into ops from generate_series(1, 101) g;
  r := pg_temp.push(a, da1, ops);
  perform pg_temp.assert('batch_of_101_rejected', pg_temp.err(r) = 'NX003' and pg_temp.msg(r) = 'batch_too_large'
     and not exists (select 1 from public.projects where id = pg_temp.u('e3000000', 1)));
  select jsonb_agg(pg_temp.op(pg_temp.u('c2000000', g), 'project', pg_temp.u('e3000000', g), 'create', null, jsonb_build_object('name', 'P' || g))) into ops from generate_series(1, 100) g;
  r := pg_temp.push(a, da1, ops);
  perform pg_temp.assert('batch_of_100_accepted', jsonb_array_length(r -> 'results') = 100 and (select bool_and(x ->> 'status' = 'applied') from jsonb_array_elements(r -> 'results') x));
  r := pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 30), 'create', null, jsonb_build_object('name', 'ok', 'description', repeat('x', 262144)));
  perform pg_temp.assert('patch_over_256kb_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'payload_too_large');
  perform pg_temp.assert('oversized_patch_not_stored', (select octet_length(patch::text) from public.sync_operations where operation_id = (r ->> 'operation_id')::uuid) < 100);
  select jsonb_agg(pg_temp.op(pg_temp.u('c3000000', g), 'project', pg_temp.u('e4000000', g), 'create', null, jsonb_build_object('name', 'big', 'description', repeat('y', 200000)))) into ops from generate_series(1, 6) g;
  r := pg_temp.push(a, da1, ops);
  perform pg_temp.assert('call_over_1mb_rejected', pg_temp.err(r) = 'NX004' and pg_temp.msg(r) = 'payload_too_large');
  r := pg_temp.push(a, da1, jsonb_build_array(
        '"not an object"'::jsonb,
        jsonb_build_object('entity_type', 'project', 'entity_id', pg_temp.u('e1000000', 40), 'op_type', 'create', 'patch', '{"name":"x"}'::jsonb),
        jsonb_build_object('operation_id', pg_temp.u('c4000000', 3), 'entity_type', 'folder', 'entity_id', pg_temp.u('e1000000', 40), 'op_type', 'create', 'patch', '{"name":"x"}'::jsonb),
        jsonb_build_object('operation_id', pg_temp.u('c4000000', 4), 'entity_type', 'project', 'entity_id', 'not-a-uuid', 'op_type', 'create', 'patch', '{"name":"x"}'::jsonb),
        jsonb_build_object('operation_id', pg_temp.u('c4000000', 5), 'entity_type', 'project', 'entity_id', pg_temp.u('e1000000', 40), 'op_type', 'upsert', 'patch', '{"name":"x"}'::jsonb)));
  perform pg_temp.assert('malformed_operations_rejected_invalid_op', (select bool_and(x ->> 'status' = 'rejected' and x ->> 'error_code' = 'invalid_op') from jsonb_array_elements(r -> 'results') x));
  perform pg_temp.assert('unusable_identity_cannot_be_recorded_and_created_nothing', not exists (select 1 from public.projects where id = pg_temp.u('e1000000', 40))
     and not exists (select 1 from public.sync_operations where operation_id in (pg_temp.u('c4000000', 3), pg_temp.u('c4000000', 4), pg_temp.u('c4000000', 5))));
  r := pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 41), 'create', null, '{"name":"x"}');
  r2 := pg_temp.one(a, da1, jsonb_build_object('operation_id', pg_temp.nid(), 'entity_type', 'project', 'entity_id', pg_temp.u('e1000000', 42), 'op_type', 'create', 'patch', '{"name":"x"}'::jsonb, 'surprise', 1));
  perform pg_temp.assert('unknown_operation_key_rejected', r2 ->> 'error_code' = 'invalid_op' and not exists (select 1 from public.projects where id = pg_temp.u('e1000000', 42)));
  r2 := pg_temp.one(a, da1, jsonb_build_object('operation_id', pg_temp.nid(), 'entity_type', 'project', 'entity_id', pg_temp.u('e1000000', 43), 'op_type', 'create', 'patch', '{"name":"x"}'::jsonb, 'client_created_at', 'yesterday-ish'));
  perform pg_temp.assert('invalid_client_timestamp_rejected', r2 ->> 'error_code' = 'invalid_op');
  r2 := pg_temp.one(a, da1, jsonb_build_object('operation_id', pg_temp.nid(), 'entity_type', 'project', 'entity_id', pg_temp.u('e1000000', 44), 'op_type', 'create', 'patch', '{"name":"x"}'::jsonb, 'client_created_at', '1999-01-01T00:00:00Z'));
  perform pg_temp.assert('client_clock_is_informational_only', r2 ->> 'status' = 'applied' and (r2 -> 'row' ->> 'created_at')::timestamptz > now() - interval '1 minute');

  ---------------------------------------------------------------- locks, device bookkeeping, immutability
  perform pg_temp.assert('push_holds_the_user_lock_until_commit', pg_temp.holds_user_lock(a));
  perform pg_temp.reg(a, pg_temp.u('d0000000', 30));
  perform pg_temp.assert('last_push_at_recorded_only_for_devices_that_pushed', (select last_push_at from public.devices where id = da1) is not null
     and (select last_push_at from public.devices where id = da2) is not null and (select last_push_at from public.devices where id = pg_temp.u('d0000000', 30)) is null);
  perform pg_temp.assert('operation_log_still_append_only', (select count(*) from public.sync_operations where user_id = a) > 0);
  begin
    update public.sync_operations set patch = '{}' where user_id = a;
    perform pg_temp.assert('operation_log_append_only_enforced', false);
  exception when sqlstate '23514' then perform pg_temp.assert('operation_log_append_only_enforced', true); end;
  perform pg_temp.assert('every_result_status_matches_its_row', not exists (select 1 from public.sync_operations where user_id = a and (result ->> 'status' <> status or result is null)));
  perform pg_temp.assert('no_conflict_rows_for_other_users', (select count(*) from public.sync_conflicts where user_id = b) = 0);
  perform pg_temp.assert('s1_invariants_survive: field_versions server owned', (select field_versions from public.projects where id = p) = '{}'::jsonb);
end $$;
select count(*) as passed from _r;
rollback;
