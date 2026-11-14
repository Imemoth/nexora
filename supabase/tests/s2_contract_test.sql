-- S2/S5 wire-contract suite (Phase 3 consolidation, workstream 1). Rollback-only.
-- Covers: version_before, conflict detail for the S5 local mirror, immutable rejected history and new-operation-id recovery,
-- sort_order mixed-field server-wins, parent_invalid under a tombstoned parent, and the CURRENT (unruled) completed_at behavior.
begin;
\ir s2_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da uuid := pg_temp.u('d0000000', 1); db uuid := pg_temp.u('d0000000', 2);
  p1 uuid := pg_temp.u('e1000000', 1); pdead uuid := pg_temp.u('e1000000', 2); pb uuid := pg_temp.u('e1000000', 3);
  t1 uuid := pg_temp.u('e2000000', 1); t2 uuid := pg_temp.u('e2000000', 2); t3 uuid := pg_temp.u('e2000000', 3);
  o1 uuid := pg_temp.u('f0000000', 1); o2 uuid := pg_temp.u('f0000000', 2); o3 uuid := pg_temp.u('f0000000', 3);
  r jsonb; r2 jsonb; res jsonb; stored jsonb; n int;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  perform pg_temp.reg(a, da); perform pg_temp.reg(b, db);
  insert into public.projects(id, owner_id, name, sort_order) values (pb, b, 'Bs secret project', 7);

  ---------------------------------------------------------------- version_before
  r := pg_temp.c(a, da, 'project', p1, 'create', null, '{"name":"Alpha","sort_order":1}');
  perform pg_temp.assert('vb_create_new_is_0', (r ->> 'version_before')::int = 0 and (r ->> 'applied_version')::int = 1);
  r := pg_temp.c(a, da, 'project', p1, 'create', null, '{"name":"Alpha","sort_order":1}');
  perform pg_temp.assert('vb_create_existing_noop_equals_version', (r ->> 'version_before')::int = 1 and (r ->> 'applied_version')::int = 1);
  r := pg_temp.c(a, da, 'project', p1, 'update', 1, '{"name":"Alpha 2"}');
  perform pg_temp.assert('vb_update_applied', r ->> 'status' = 'applied' and (r ->> 'version_before')::int = 1 and (r ->> 'applied_version')::int = 2);
  r := pg_temp.c(a, da, 'project', p1, 'update', 2, '{"name":"Alpha 2"}');
  perform pg_temp.assert('vb_update_noop_merge_equal', (r ->> 'version_before')::int = 2 and (r ->> 'applied_version')::int = 2);
  r := pg_temp.c(a, da, 'project', p1, 'update', 2, '{}');
  perform pg_temp.assert('vb_update_empty_patch', (r ->> 'version_before')::int = 2 and (r ->> 'applied_version')::int = 2);

  -- replay is deterministic: original result, including version_before, even after the entity moved on
  o1 := pg_temp.nid();
  r := pg_temp.one(a, da, pg_temp.op(o1, 'project', p1, 'update', 2, '{"color":"#112233"}'));
  perform pg_temp.assert('vb_replay_setup', r ->> 'status' = 'applied' and (r ->> 'version_before')::int = 2 and (r ->> 'applied_version')::int = 3);
  r2 := pg_temp.c(a, da, 'project', p1, 'update', 3, '{"description":"later"}');
  perform pg_temp.assert('vb_entity_moved_on', (r2 ->> 'applied_version')::int = 4);
  r2 := pg_temp.one(a, da, pg_temp.op(o1, 'project', p1, 'update', 2, '{"color":"#112233"}'));
  perform pg_temp.assert('vb_replay_returns_original_version_before', r2 ->> 'replayed' = 'true' and (r2 ->> 'version_before')::int = 2
     and (r2 ->> 'applied_version')::int = 3);
  perform pg_temp.assert('vb_replay_identical_except_replayed', (r2 - 'replayed') = (r - 'replayed'));
  perform pg_temp.assert('vb_stored_result_has_version_before', (select (result ->> 'version_before')::int from public.sync_operations
                           where user_id = a and operation_id = o1) = 2);

  r := pg_temp.c(a, da, 'project', p1, 'delete', 4);
  perform pg_temp.assert('vb_delete_applied', r ->> 'status' = 'applied' and (r ->> 'version_before')::int = 4 and (r ->> 'applied_version')::int = 5);
  r := pg_temp.c(a, da, 'project', p1, 'delete', 5);
  perform pg_temp.assert('vb_delete_already_tombstoned_noop', r ->> 'status' = 'applied' and (r ->> 'version_before')::int = 5
     and (r ->> 'applied_version')::int = 5);
  perform pg_temp.assert('vb_rejected_has_no_version_before', not (pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 99), 'update', 1, '{"name":"x"}') ? 'version_before'));

  ---------------------------------------------------------------- conflict detail (S5 mirror)
  perform pg_temp.c(a, da, 'project', pdead, 'create', null, '{"name":"Live","sort_order":1}');            -- v1
  perform pg_temp.c(a, da, 'project', pdead, 'update', 1, '{"name":"Server name"}');                       -- v2, name fv=2
  r := pg_temp.c(a, da, 'project', pdead, 'update', 1, '{"name":"Client name"}');
  perform pg_temp.assert('cd_field_conflict_status', r ->> 'status' = 'conflict' and r ? 'conflict_id' and (r ->> 'version_before')::int = 2);
  perform pg_temp.assert('cd_field_conflict_object', r -> 'conflict' ->> 'kind' = 'field' and r -> 'conflict' -> 'fields' = '["name"]'::jsonb
     and (r -> 'conflict' ->> 'base_version')::int = 1 and (r -> 'conflict' ->> 'server_version')::int = 2
     and r -> 'conflict' -> 'server_value' = '{"name":"Server name"}'::jsonb and r -> 'conflict' -> 'client_value' = '{"name":"Client name"}'::jsonb
     and r -> 'conflict' ->> 'status' = 'open');
  perform pg_temp.assert('cd_conflict_matches_row', (select kind = 'field' and server_value = r -> 'conflict' -> 'server_value'
        and client_value = r -> 'conflict' -> 'client_value' and server_version = 2 and base_version = 1
      from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid));
  perform pg_temp.assert('cd_conflict_nothing_applied', (select name from public.projects where id = pdead) = 'Server name');
  perform pg_temp.assert('cd_conflict_row_is_current_server_row', r -> 'row' ->> 'name' = 'Server name');
  -- replay returns the identical conflict detail
  stored := (select result from public.sync_operations where user_id = a and operation_id = (select operation_id from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid));
  perform pg_temp.assert('cd_stored_result_contains_conflict', stored -> 'conflict' = r -> 'conflict');
  -- the entity is blocked until S3 resolves it
  perform pg_temp.assert('cd_blocked_after_conflict', pg_temp.c(a, da, 'project', pdead, 'update', 2, '{"color":"#000000"}') ->> 'error_code' = 'blocked_by_conflict');

  -- delete conflicts carry detail too
  perform pg_temp.c(a, da, 'project', t3, 'create', null, '{"name":"Del target"}');
  perform pg_temp.c(a, da, 'project', t3, 'update', 1, '{"name":"Del target 2"}');
  r := pg_temp.c(a, da, 'project', t3, 'delete', 1);
  perform pg_temp.assert('cd_delete_edited_detail', r ->> 'status' = 'conflict' and r -> 'conflict' ->> 'kind' = 'delete_edited'
     and r -> 'conflict' -> 'fields' = '["deleted_at"]'::jsonb and (r -> 'conflict' ->> 'server_version')::int = 2);

  -- no leak: another user's id is indistinguishable from a missing one and has no conflict object
  r := pg_temp.c(a, da, 'project', pb, 'update', 1, '{"name":"steal"}');
  perform pg_temp.assert('cd_foreign_update_not_found_no_leak', r ->> 'error_code' = 'not_found' and not (r ? 'conflict') and not (r ? 'row')
     and not (r::text like '%secret%'));
  r := pg_temp.c(a, da, 'project', pb, 'create', null, '{"name":"steal"}');
  perform pg_temp.assert('cd_foreign_create_not_found_no_leak', r ->> 'error_code' = 'not_found' and not (r ? 'conflict') and not (r::text like '%secret%'));
  r := pg_temp.c(a, da, 'project', pb, 'delete', 1);
  perform pg_temp.assert('cd_foreign_delete_not_found_no_leak', r ->> 'error_code' = 'not_found' and not (r::text like '%secret%'));
  -- user B cannot replay A's operation id to read its stored result
  r := pg_temp.one(b, db, pg_temp.op(o1, 'project', p1, 'update', 2, '{"color":"#112233"}'));
  perform pg_temp.assert('cd_other_user_same_operation_id_is_independent', r ->> 'replayed' = 'false' and r ->> 'error_code' = 'not_found'
     and not (r::text like '%Alpha%'));

  ---------------------------------------------------------------- rejected history is immutable; recovery uses a new operation id
  o2 := pg_temp.nid();
  r := pg_temp.one(a, da, pg_temp.op(o2, 'project', pg_temp.u('e1000000', 50), 'create', null, '{"description":"no name"}'));
  perform pg_temp.assert('rj_first_attempt_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch');
  stored := (select to_jsonb(s) from public.sync_operations s where user_id = a and operation_id = o2);
  perform pg_temp.assert('rj_rejected_is_recorded', stored is not null and stored ->> 'status' = 'rejected');
  -- same id, corrected payload: refused, not recorded, history unchanged
  r := pg_temp.one(a, da, pg_temp.op(o2, 'project', pg_temp.u('e1000000', 50), 'create', null, '{"name":"fixed"}'));
  perform pg_temp.assert('rj_same_id_corrected_payload_is_operation_id_reuse', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'operation_id_reuse');
  perform pg_temp.assert('rj_history_unchanged', (select to_jsonb(s) from public.sync_operations s where user_id = a and operation_id = o2) = stored);
  perform pg_temp.assert('rj_no_entity_created_by_reuse', not exists (select 1 from public.projects where id = pg_temp.u('e1000000', 50)));
  -- same id, same payload: replays the stored rejection
  r := pg_temp.one(a, da, pg_temp.op(o2, 'project', pg_temp.u('e1000000', 50), 'create', null, '{"description":"no name"}'));
  perform pg_temp.assert('rj_same_payload_replays_rejection', r ->> 'error_code' = 'invalid_patch' and r ->> 'replayed' = 'true');
  -- recovery: a NEW operation id with the corrected payload succeeds; both history rows survive
  o3 := pg_temp.nid();
  r := pg_temp.one(a, da, pg_temp.op(o3, 'project', pg_temp.u('e1000000', 50), 'create', null, '{"name":"fixed"}'));
  perform pg_temp.assert('rj_recovery_with_new_operation_id', r ->> 'status' = 'applied' and (r ->> 'version_before')::int = 0);
  perform pg_temp.assert('rj_both_history_rows_exist', (select count(*) from public.sync_operations where user_id = a and operation_id in (o2, o3)) = 2
     and (select status from public.sync_operations where user_id = a and operation_id = o2) = 'rejected');
  -- append-only: no UPDATE or DELETE of history (even as the table owner)
  begin update public.sync_operations set status = 'applied' where user_id = a and operation_id = o2;
    perform pg_temp.assert('rj_update_history_blocked', false);
  exception when others then perform pg_temp.assert('rj_update_history_blocked', true); end;
  begin delete from public.sync_operations where user_id = a and operation_id = o2;
    perform pg_temp.assert('rj_delete_history_blocked', false);
  exception when others then perform pg_temp.assert('rj_delete_history_blocked', true); end;

  ---------------------------------------------------------------- sort_order mixed-field update: server wins for sort_order only
  perform pg_temp.c(a, da, 'project', t2, 'create', null, '{"name":"Mixed","sort_order":1}');             -- v1
  perform pg_temp.c(a, da, 'project', t2, 'update', 1, '{"sort_order":5}');                                -- v2, sort_order fv=2
  r := pg_temp.c(a, da, 'project', t2, 'update', 1, '{"name":"Mixed renamed","sort_order":9}');
  perform pg_temp.assert('so_mixed_applied_with_auto_resolved', r ->> 'status' = 'applied' and r ->> 'auto_resolved' = 'true'
     and r -> 'row' ->> 'name' = 'Mixed renamed' and (r -> 'row' ->> 'sort_order')::int = 5);
  perform pg_temp.assert('so_mixed_version_before_and_applied', (r ->> 'version_before')::int = 2 and (r ->> 'applied_version')::int = 3);
  perform pg_temp.assert('so_mixed_conflict_detail', r -> 'conflict' ->> 'status' = 'resolved_server' and r -> 'conflict' -> 'fields' = '["sort_order"]'::jsonb
     and r -> 'conflict' -> 'server_value' = '{"sort_order":5}'::jsonb and r -> 'conflict' -> 'client_value' = '{"sort_order":9}'::jsonb);
  perform pg_temp.assert('so_mixed_audit_row_resolved_not_open', (select status = 'resolved_server' and resolution_source = 'auto_policy'
        and resolution_policy = 'sort_order_server_wins' from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid));
  perform pg_temp.assert('so_mixed_does_not_block_entity', pg_temp.c(a, da, 'project', t2, 'update', 3, '{"color":"#abcdef"}') ->> 'status' = 'applied');
  -- sort_order together with a REAL conflict: whole operation is a conflict, nothing applied (D-A)
  perform pg_temp.c(a, da, 'project', t1, 'create', null, '{"name":"Real","sort_order":1}');
  perform pg_temp.c(a, da, 'project', t1, 'update', 1, '{"name":"Real server","sort_order":2}');
  r := pg_temp.c(a, da, 'project', t1, 'update', 1, '{"name":"Real client","sort_order":8}');
  perform pg_temp.assert('so_with_real_conflict_is_whole_conflict', r ->> 'status' = 'conflict' and r -> 'conflict' -> 'fields' = '["name","sort_order"]'::jsonb
     and (select name from public.projects where id = t1) = 'Real server' and (select sort_order from public.projects where id = t1) = 2);

  ---------------------------------------------------------------- tombstoned parent on create
  r := pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 40), 'create', null, jsonb_build_object('project_id', p1, 'title', 'Under dead project'));
  perform pg_temp.assert('pi_create_under_tombstoned_project', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'parent_invalid');
  perform pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 60), 'create', null, '{"name":"Live host"}');
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 41), 'create', null, jsonb_build_object('project_id', pg_temp.u('e1000000', 60), 'title', 'Parent'));
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 41), 'delete', 1);
  r := pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 42), 'create', null,
                 jsonb_build_object('project_id', pg_temp.u('e1000000', 60), 'parent_id', pg_temp.u('e2000000', 41), 'title', 'Under dead task'));
  perform pg_temp.assert('pi_create_under_tombstoned_task', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'parent_invalid');
  perform pg_temp.assert('pi_nothing_created', not exists (select 1 from public.tasks where id in (pg_temp.u('e2000000', 40), pg_temp.u('e2000000', 42))));
  perform pg_temp.assert('pi_rejection_is_recorded', (select count(*) from public.sync_operations where user_id = a and status = 'rejected' and result ->> 'error_code' = 'parent_invalid') = 2);

  ---------------------------------------------------------------- completed_at/status: CURRENT behavior (no approved rule; see wire contract section 7)
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 70), 'create', null, jsonb_build_object('project_id', pg_temp.u('e1000000', 60), 'title', 'Ca'));
  r := pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 70), 'update', 1, '{"status":"done"}');
  perform pg_temp.assert('ca_current_done_without_completed_at_is_accepted', r ->> 'status' = 'applied' and r -> 'row' ->> 'completed_at' is null);
  r := pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 70), 'update', 2, '{"completed_at":"2026-11-12T10:00:00Z"}');
  perform pg_temp.assert('ca_current_completed_at_is_plain_field', r ->> 'status' = 'applied' and r -> 'row' ->> 'completed_at' is not null);

  select count(*) into n from _r;
  raise notice 'assertions=%', n;
end $$;
select 'S2 contract suite: ' || count(*) || ' assertions passed' from _r;
rollback;
