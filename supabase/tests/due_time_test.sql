-- Due time suite (ADR 0004; migration 20261116100000_nexora_due_time.sql). Rollback-only.
-- Covers: capability advertisement, create/update/clear of the time, validation, the date/time pairing rule for older
-- clients (a stale time never survives a date change), field versions, conflicts and every resolution strategy that
-- involves the time, replay, pull, and that direct writes stay revoked.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); da1 uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2);
  p1 uuid := pg_temp.u('e1000000', 1);
  t1 uuid := pg_temp.u('e2000000', 1); t2 uuid := pg_temp.u('e2000000', 2); t3 uuid := pg_temp.u('e2000000', 3);
  t4 uuid := pg_temp.u('e2000000', 4); t5 uuid := pg_temp.u('e2000000', 5); t6 uuid := pg_temp.u('e2000000', 6);
  tcopy uuid := pg_temp.u('e2000000', 99);
  r jsonb; r2 jsonb; cid uuid; o uuid; s0 bigint; pull jsonb;
begin
  perform pg_temp.mkuser(a);
  r := pg_temp.reg(a, da1); perform pg_temp.reg(a, da2);
  perform pg_temp.assert('cap_register_advertises_due_time', r -> 'features' ? 'due_time');
  perform pg_temp.assert('cap_register_keeps_old_keys', r ? 'device_id' and r ? 'created' and r ? 'active_devices');
  perform pg_temp.c(a, da1, 'project', p1, 'create', null, '{"name":"P"}');

  ---------------------------------------------------------------- create
  r := pg_temp.c(a, da1, 'task', t1, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Date only', 'due_date', '2026-11-20'));
  perform pg_temp.assert('cr_date_only_has_no_time', r ->> 'status' = 'applied' and r -> 'row' -> 'due_time' = 'null'::jsonb and r -> 'row' ->> 'due_date' = '2026-11-20');
  r := pg_temp.c(a, da1, 'task', t2, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Timed', 'due_date', '2026-11-20', 'due_time', '17:30'));
  perform pg_temp.assert('cr_with_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_time' = '17:30:00' and r -> 'row' ->> 'due_date' = '2026-11-20');
  r := pg_temp.c(a, da1, 'task', t3, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Undated'));
  perform pg_temp.assert('cr_undated_has_no_time', r -> 'row' -> 'due_time' = 'null'::jsonb and r -> 'row' -> 'due_date' = 'null'::jsonb);
  perform pg_temp.assert('cr_midnight_is_a_time_not_null', (pg_temp.c(a, da1, 'task', t4, 'create', null,
     jsonb_build_object('project_id', p1, 'title', 'Midnight', 'due_date', '2026-11-20', 'due_time', '00:00')) -> 'row' ->> 'due_time') = '00:00:00');
  -- validation: nothing is applied and the rejection is terminal
  r := pg_temp.c(a, da1, 'task', t5, 'create', null, jsonb_build_object('project_id', p1, 'title', 'x', 'due_time', '09:00'));
  perform pg_temp.assert('cr_time_without_date_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('cr_rejected_applied_nothing', not exists (select 1 from public.tasks where id = t5));
  perform pg_temp.assert('cr_seconds_rejected', pg_temp.c(a, da1, 'task', t5, 'create', null,
     jsonb_build_object('project_id', p1, 'title', 'x', 'due_date', '2026-11-20', 'due_time', '09:00:30')) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('cr_hour_24_rejected', pg_temp.c(a, da1, 'task', t5, 'create', null,
     jsonb_build_object('project_id', p1, 'title', 'x', 'due_date', '2026-11-20', 'due_time', '24:00')) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('cr_garbage_rejected', pg_temp.c(a, da1, 'task', t5, 'create', null,
     jsonb_build_object('project_id', p1, 'title', 'x', 'due_date', '2026-11-20', 'due_time', 'noon')) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('cr_number_rejected', pg_temp.c(a, da1, 'task', t5, 'create', null,
     jsonb_build_object('project_id', p1, 'title', 'x', 'due_date', '2026-11-20', 'due_time', 930)) ->> 'error_code' = 'invalid_patch');

  ---------------------------------------------------------------- update, clear
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"due_time":"08:15"}');
  perform pg_temp.assert('up_add_time_to_date_only', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_time' = '08:15:00' and r -> 'row' ->> 'due_date' = '2026-11-20'
     and (r -> 'row' -> 'field_versions' ->> 'due_time')::int = 2 and not (r -> 'row' -> 'field_versions' ? 'due_date' and (r -> 'row' -> 'field_versions' ->> 'due_date')::int = 2));
  r := pg_temp.c(a, da1, 'task', t1, 'update', 2, '{"due_time":"09:45"}');
  perform pg_temp.assert('up_change_time', r -> 'row' ->> 'due_time' = '09:45:00');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 3, '{"due_time":null}');
  perform pg_temp.assert('up_clear_time_keeps_date', r ->> 'status' = 'applied' and r -> 'row' -> 'due_time' = 'null'::jsonb and r -> 'row' ->> 'due_date' = '2026-11-20');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 4, '{"due_time":null}');
  perform pg_temp.assert('up_clear_time_again_is_a_noop', (r ->> 'version_before')::int = 4 and (r ->> 'applied_version')::int = 4);
  r := pg_temp.c(a, da1, 'task', t3, 'update', 1, '{"due_time":"10:00"}');
  perform pg_temp.assert('up_time_on_undated_task_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t3, 'update', 1, '{"due_date":"2026-12-01","due_time":"10:00"}');
  perform pg_temp.assert('up_date_and_time_together', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_time' = '10:00:00' and r -> 'row' ->> 'due_date' = '2026-12-01');

  ---------------------------------------------------------------- older client: a date change never leaves a stale time
  -- t2 has 2026-11-20 17:30 (version 1). An older client moves the date and knows nothing about the time.
  r := pg_temp.c(a, da1, 'task', t2, 'update', 1, '{"due_date":"2026-11-25"}');
  perform pg_temp.assert('old_date_change_clears_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_date' = '2026-11-25' and r -> 'row' -> 'due_time' = 'null'::jsonb);
  perform pg_temp.assert('old_date_change_is_one_version', (r ->> 'applied_version')::int = 2 and (r ->> 'version_before')::int = 1);
  perform pg_temp.assert('old_date_change_tracks_the_time_field', (r -> 'row' -> 'field_versions' ->> 'due_time')::int = 2);
  -- ... clearing the date also clears the time (the check constraint would refuse the alternative)
  perform pg_temp.c(a, da1, 'task', t2, 'update', 2, '{"due_date":"2026-11-26","due_time":"06:00"}');          -- v3: date + time
  r := pg_temp.c(a, da1, 'task', t2, 'update', 3, '{"due_date":null}');
  perform pg_temp.assert('old_clear_date_clears_time', r ->> 'status' = 'applied' and r -> 'row' -> 'due_date' = 'null'::jsonb and r -> 'row' -> 'due_time' = 'null'::jsonb);
  -- a task without a time stays without one; the rule never invents a key
  r := pg_temp.c(a, da1, 'task', t4, 'update', 1, '{"due_time":null}');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 4, '{"due_date":"2026-11-30"}');
  perform pg_temp.assert('old_date_change_without_time_is_a_plain_update', r ->> 'status' = 'applied' and r -> 'row' -> 'due_time' = 'null'::jsonb
     and not exists (select 1 from public.tasks where id = t1 and field_versions ? 'due_time' and (field_versions ->> 'due_time')::int > 4));
  -- an unchanged date does not clear the time
  perform pg_temp.c(a, da1, 'task', t1, 'update', 5, '{"due_time":"11:11"}');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 6, '{"due_date":"2026-11-30"}');
  perform pg_temp.assert('same_date_keeps_time', (r ->> 'version_before')::int = 6 and (r ->> 'applied_version')::int = 6 and r -> 'row' ->> 'due_time' = '11:11:00');
  -- a client that knows the time moves the date and keeps the time by sending both
  r := pg_temp.c(a, da1, 'task', t1, 'update', 6, '{"due_date":"2026-12-24","due_time":"11:11"}');
  perform pg_temp.assert('new_client_moves_date_keeps_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_date' = '2026-12-24' and r -> 'row' ->> 'due_time' = '11:11:00');
  -- the task can be tombstoned and its row stays valid
  perform pg_temp.assert('tree_delete_unaffected', pg_temp.c(a, da1, 'task', t4, 'delete', 2) ->> 'status' = 'applied');

  ---------------------------------------------------------------- conflicts on the time
  perform pg_temp.c(a, da1, 'task', t6, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Conflicts', 'due_date', '2026-11-20', 'due_time', '10:00'));   -- v1
  perform pg_temp.c(a, da1, 'task', t6, 'update', 1, '{"due_time":"11:00"}');                                       -- v2 (A)
  r := pg_temp.c(a, da2, 'task', t6, 'update', 1, '{"due_time":"12:00"}');                                          -- B, same base
  perform pg_temp.assert('cf_same_time_field_conflicts', r ->> 'status' = 'conflict' and r -> 'conflict' ->> 'kind' = 'field'
     and r -> 'conflict' -> 'fields' = '["due_time"]'::jsonb);
  perform pg_temp.assert('cf_values_are_both_kept', r -> 'conflict' -> 'server_value' = '{"due_time":"11:00:00"}'::jsonb
     and r -> 'conflict' -> 'client_value' = '{"due_time":"12:00"}'::jsonb);
  perform pg_temp.assert('cf_nothing_applied', (select due_time from public.tasks where id = t6) = '11:00');
  cid := (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('cf_blocked_until_resolved', pg_temp.c(a, da2, 'task', t6, 'update', 2, '{"title":"x"}') ->> 'error_code' = 'blocked_by_conflict');
  r := pg_temp.res(a, da2, cid, 'resolved_client');
  perform pg_temp.assert('cf_resolve_client_applies_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_time' = '12:00:00');
  -- date/time crossing: A (older client) moves the date, which clears the time; B sets the time on the old base
  perform pg_temp.c(a, da1, 'task', t6, 'update', 3, '{"due_date":"2026-12-01"}');                                   -- v4 clears the time
  r := pg_temp.c(a, da2, 'task', t6, 'update', 3, '{"due_time":"13:00"}');
  perform pg_temp.assert('cf_time_edit_after_cleared_by_date_change_conflicts', r ->> 'status' = 'conflict' and r -> 'conflict' -> 'fields' = '["due_time"]'::jsonb
     and r -> 'conflict' -> 'server_value' = '{"due_time":null}'::jsonb);
  cid := (r ->> 'conflict_id')::uuid;
  r := pg_temp.res(a, da2, cid, 'resolved_server');
  perform pg_temp.assert('cf_resolve_server_keeps_cleared_time', r ->> 'status' = 'applied' and r -> 'row' -> 'due_time' = 'null'::jsonb and r -> 'row' ->> 'due_date' = '2026-12-01');
  -- merged: both fields at once
  perform pg_temp.c(a, da1, 'task', t6, 'update', 4, '{"due_time":"14:00"}');                                       -- v5
  r := pg_temp.c(a, da2, 'task', t6, 'update', 4, '{"due_time":"15:00","title":"B title"}');
  cid := (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('cf_merged_conflict_lists_time_only', r -> 'conflict' -> 'fields' = '["due_time"]'::jsonb);
  r := pg_temp.res(a, da2, cid, 'resolved_merged', '{"due_date":"2027-01-05","due_time":"16:30"}');
  perform pg_temp.assert('cf_resolve_merged_sets_date_and_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_date' = '2027-01-05' and r -> 'row' ->> 'due_time' = '16:30:00');
  r := pg_temp.c(a, da1, 'task', t6, 'update', 6, '{"due_time":"17:00"}');
  perform pg_temp.assert('cf_after_merge_the_task_edits_normally', r ->> 'status' = 'applied');
  -- merged with a time but no date is refused and leaves the conflict open
  perform pg_temp.c(a, da1, 'task', t6, 'update', 7, '{"due_time":"18:00"}');                                       -- v8
  r := pg_temp.c(a, da2, 'task', t6, 'update', 7, '{"due_time":"19:00"}');
  cid := (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('cf_merged_time_without_date_rejected', pg_temp.res(a, da2, cid, 'resolved_merged', '{"due_date":null,"due_time":"19:00"}') ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('cf_rejected_resolution_leaves_conflict_open', (select status from public.sync_conflicts where id = cid) = 'open');
  -- an older client's conflicting date edit resolved as "mine" does not leave a stale time
  perform pg_temp.res(a, da2, cid, 'resolved_server');
  perform pg_temp.c(a, da1, 'task', t6, 'update', 8, '{"due_date":"2027-02-01","due_time":"07:00"}');               -- v9
  r := pg_temp.c(a, da2, 'task', t6, 'update', 8, '{"due_date":"2027-03-01"}');
  perform pg_temp.assert('cf_old_client_date_conflict', r ->> 'status' = 'conflict' and r -> 'conflict' -> 'fields' = '["due_date"]'::jsonb);
  r := pg_temp.res(a, da2, (r ->> 'conflict_id')::uuid, 'resolved_client');
  perform pg_temp.assert('cf_resolved_client_date_clears_stale_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_date' = '2027-03-01' and r -> 'row' -> 'due_time' = 'null'::jsonb);

  ---------------------------------------------------------------- recreate_copy carries the time
  perform pg_temp.c(a, da1, 'task', t5, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Doomed', 'due_date', '2026-11-20', 'due_time', '21:00'));
  perform pg_temp.c(a, da1, 'task', t5, 'delete', 1);
  r := pg_temp.c(a, da2, 'task', t5, 'update', 1, '{"title":"Late edit"}');
  r := pg_temp.res(a, da2, (r ->> 'conflict_id')::uuid, 'recreate_copy', jsonb_build_object('new_entity_id', tcopy));
  perform pg_temp.assert('rc_copy_keeps_date_and_time', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_date' = '2026-11-20' and r -> 'row' ->> 'due_time' = '21:00:00');

  ---------------------------------------------------------------- replay and pull
  o := pg_temp.nid();
  r := pg_temp.one(a, da1, pg_temp.op(o, 'task', t1, 'update', 7, '{"due_time":"22:22"}'));
  r2 := pg_temp.one(a, da1, pg_temp.op(o, 'task', t1, 'update', 7, '{"due_time":"22:22"}'));
  perform pg_temp.assert('rp_replay_returns_original', r2 ->> 'replayed' = 'true' and (r2 - 'replayed') = (r - 'replayed'));
  perform pg_temp.assert('rp_changed_time_under_same_id_is_reuse', pg_temp.one(a, da1, pg_temp.op(o, 'task', t1, 'update', 7, '{"due_time":"23:23"}')) ->> 'error_code' = 'operation_id_reuse');
  pull := pg_temp.pull_all(a, da2, 0);
  perform pg_temp.assert('pl_pull_carries_the_time', exists (select 1 from jsonb_array_elements(pull -> 'changes') c
      where c -> 'row' ->> 'id' = t1::text and c -> 'row' ->> 'due_time' = '22:22:00'));
  perform pg_temp.assert('pl_pull_date_only_task_has_null_time', exists (select 1 from jsonb_array_elements(pull -> 'changes') c
      where c -> 'row' ->> 'id' = t3::text and c -> 'row' ? 'due_time'));

  ---------------------------------------------------------------- direct writes stay revoked (S9)
  perform pg_temp.assert('s9_direct_time_write_refused', pg_temp.err(pg_temp.rpc(a, format('select to_jsonb(count(*)) from (update public.tasks set due_time = %L where id = %L returning 1) x', '10:00', t1))) is not null);
  perform pg_temp.assert('s9_client_cannot_supply_field_versions', pg_temp.c(a, da1, 'task', t1, 'update', 8, '{"field_versions":{"due_time":1}}') ->> 'error_code' = 'invalid_patch');

  select count(*) into s0 from _r;
  raise notice 'assertions=%', s0;
end $$;
select 'due time suite: ' || count(*) || ' assertions passed' from _r;
rollback;
