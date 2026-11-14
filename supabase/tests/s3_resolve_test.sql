-- S3 conflict resolution suite. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1); gone uuid := pg_temp.u('99999999', 1); anon_u uuid := pg_temp.u('aa000000', 1);
  da1 uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2); db1 uuid := pg_temp.u('d0000000', 3); drev uuid := pg_temp.u('d0000000', 4);
  p1 uuid := pg_temp.u('e1000000', 1); p2 uuid := pg_temp.u('e1000000', 2); pb uuid := pg_temp.u('e1000000', 3);
  t1 uuid := pg_temp.u('e2000000', 1); t2 uuid := pg_temp.u('e2000000', 2); t3 uuid := pg_temp.u('e2000000', 3);
  tp uuid := pg_temp.u('e2000000', 4); tc uuid := pg_temp.u('e2000000', 5); t6 uuid := pg_temp.u('e2000000', 6);
  r jsonb; r2 jsonb; cid uuid; cid2 uuid; op uuid; c public.sync_conflicts; n0 int; s0 bigint; copy uuid := pg_temp.u('e2000000', 99);
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  insert into auth.users(id, is_anonymous) values (anon_u, true);
  perform pg_temp.reg(a, da1); perform pg_temp.reg(a, da2); perform pg_temp.reg(b, db1); perform pg_temp.reg(a, drev);
  perform pg_temp.c(a, da1, 'project', p1, 'create', null, '{"name":"Alpha","sort_order":1}');            -- p1 v1
  perform pg_temp.c(a, da1, 'project', p2, 'create', null, '{"name":"Beta"}');
  insert into public.projects(id, owner_id, name) values (pb, b, 'Bs');

  ---------------------------------------------------------------- field conflict: resolved_server
  perform pg_temp.c(a, da1, 'project', p1, 'update', 1, '{"name":"Theirs"}');                                -- v2
  r := pg_temp.c(a, da2, 'project', p1, 'update', 1, '{"name":"Mine"}');
  perform pg_temp.assert('fc_conflict_open', r ->> 'status' = 'conflict');
  cid := (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('fc_entity_blocked_while_open', pg_temp.c(a, da1, 'project', p1, 'update', 2, '{"color":"#111111"}') ->> 'error_code' = 'blocked_by_conflict');
  op := pg_temp.nid(); s0 := pg_temp.maxseq(a);
  r := pg_temp.resolve(a, da2, op, cid, 'resolved_server');
  perform pg_temp.assert('rs_applied_without_change', r ->> 'status' = 'applied' and r ->> 'resolution' = 'resolved_server' and not (r ? 'applied_version')
     and r -> 'row' ->> 'name' = 'Theirs' and (r ->> 'version_before')::int = 2 and r ->> 'replayed' = 'false');
  select * into c from public.sync_conflicts where id = cid;
  perform pg_temp.assert('rs_conflict_resolved_by_user', c.status = 'resolved_server' and c.resolution_source = 'user' and c.resolution_operation_id = op and c.resolved_at is not null);
  perform pg_temp.assert('rs_evidence_preserved', c.server_value = '{"name":"Theirs"}' and c.client_value = '{"name":"Mine"}' and c.fields = array['name']);
  perform pg_temp.assert('rs_resolution_recorded_as_operation', (select op_type = 'resolve' and status = 'applied' and base_version is null and (result - 'replayed') = (r - 'replayed')
      from public.sync_operations where user_id = a and operation_id = op));
  perform pg_temp.assert('rs_conflict_enters_the_change_stream_again', c.change_seq > s0);
  perform pg_temp.assert('rs_entity_unblocked', pg_temp.c(a, da1, 'project', p1, 'update', 2, '{"color":"#111111"}') ->> 'status' = 'applied');
  -- idempotency
  perform pg_temp.c(a, da1, 'project', p1, 'update', 3, '{"description":"moved on"}');
  r2 := pg_temp.resolve(a, da2, op, cid, 'resolved_server');
  perform pg_temp.assert('rs_replay_returns_original', r2 ->> 'replayed' = 'true' and (r2 - 'replayed') = (r - 'replayed') and r2 -> 'row' ->> 'name' = 'Theirs');
  perform pg_temp.assert('rs_same_id_other_strategy_is_operation_id_reuse', pg_temp.resolve(a, da2, op, cid, 'resolved_client') ->> 'error_code' = 'operation_id_reuse');
  perform pg_temp.assert('rs_history_unchanged_after_reuse', (select status from public.sync_conflicts where id = cid) = 'resolved_server');
  r2 := pg_temp.res(a, da2, cid, 'resolved_client');
  perform pg_temp.assert('rs_already_resolved_is_rejected_and_recorded', r2 ->> 'status' = 'rejected' and r2 ->> 'error_code' = 'conflict_not_open'
     and exists (select 1 from public.sync_operations where user_id = a and operation_id = (r2 ->> 'operation_id')::uuid and status = 'rejected' and op_type = 'resolve'));
  perform pg_temp.assert('rs_resolved_conflict_is_final', (select status from public.sync_conflicts where id = cid) = 'resolved_server');

  ---------------------------------------------------------------- resolved_client
  perform pg_temp.c(a, da1, 'project', p2, 'update', 1, '{"name":"B-theirs"}');                               -- p2 v2
  r := pg_temp.c(a, da2, 'project', p2, 'update', 1, '{"name":"B-mine"}');
  cid := (r ->> 'conflict_id')::uuid;
  r := pg_temp.res(a, da2, cid, 'resolved_client');
  perform pg_temp.assert('rc_applies_client_value_at_current_version', r ->> 'status' = 'applied' and r -> 'row' ->> 'name' = 'B-mine'
     and (r ->> 'applied_version')::int = 3 and (r ->> 'version_before')::int = 2);
  perform pg_temp.assert('rc_field_versions_updated', (select field_versions ->> 'name' from public.projects where id = p2) = '3');
  perform pg_temp.assert('rc_status_resolved_client', (select status from public.sync_conflicts where id = cid) = 'resolved_client');

  ---------------------------------------------------------------- resolved_merged
  perform pg_temp.c(a, da1, 'project', p2, 'update', 3, '{"name":"B-v4"}');
  r := pg_temp.c(a, da2, 'project', p2, 'update', 3, '{"name":"B-mine2"}');
  cid := (r ->> 'conflict_id')::uuid;
  n0 := (select count(*) from public.sync_operations where user_id = a);
  perform pg_temp.assert('rm_without_values_rejected', pg_temp.res(a, da2, cid, 'resolved_merged') ->> 'error_code' = 'invalid_values');
  perform pg_temp.assert('rm_empty_values_rejected', pg_temp.res(a, da2, cid, 'resolved_merged', '{}') ->> 'error_code' = 'invalid_values');
  perform pg_temp.assert('rm_unknown_key_rejected', pg_temp.res(a, da2, cid, 'resolved_merged', '{"owner_id":"x"}') ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('rm_wrong_type_rejected', pg_temp.res(a, da2, cid, 'resolved_merged', '{"name":5}') ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('rm_rejections_leave_conflict_open_and_data_unchanged',
     (select status from public.sync_conflicts where id = cid) = 'open' and (select name from public.projects where id = p2) = 'B-v4');
  r := pg_temp.res(a, da2, cid, 'resolved_merged', '{"name":"B-merged","sort_order":4}');
  perform pg_temp.assert('rm_applies_merged_values', r ->> 'status' = 'applied' and r -> 'row' ->> 'name' = 'B-merged' and (r -> 'row' ->> 'sort_order')::int = 4);
  perform pg_temp.assert('rm_both_original_values_still_in_conflict', (select server_value = '{"name":"B-v4"}' and client_value = '{"name":"B-mine2"}'
       and status = 'resolved_merged' from public.sync_conflicts where id = cid));

  ---------------------------------------------------------------- edit_deleted: recreate as a copy (tombstones stay permanent)
  perform pg_temp.c(a, da1, 'task', t1, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Doomed', 'notes', 'keep me', 'priority', 'high'));
  perform pg_temp.c(a, da1, 'task', t1, 'delete', 1);                                                          -- tombstone v2
  r := pg_temp.c(a, da2, 'task', t1, 'update', 1, '{"title":"Late edit"}');
  perform pg_temp.assert('ed_conflict_kind', r ->> 'status' = 'conflict' and r -> 'conflict' ->> 'kind' = 'edit_deleted');
  cid := (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('ed_client_strategy_not_allowed', pg_temp.res(a, da2, cid, 'resolved_client') ->> 'error_code' = 'strategy_not_allowed');
  perform pg_temp.assert('ed_merged_strategy_not_allowed', pg_temp.res(a, da2, cid, 'resolved_merged', '{"title":"x"}') ->> 'error_code' = 'strategy_not_allowed');
  perform pg_temp.assert('ed_copy_needs_new_id', pg_temp.res(a, da2, cid, 'recreate_copy') ->> 'error_code' = 'invalid_values');
  perform pg_temp.assert('ed_copy_rejects_malformed_id', pg_temp.res(a, da2, cid, 'recreate_copy', '{"new_entity_id":"nope"}') ->> 'error_code' = 'invalid_values');
  perform pg_temp.assert('ed_copy_rejects_taken_id', pg_temp.res(a, da2, cid, 'recreate_copy', jsonb_build_object('new_entity_id', t1)) ->> 'error_code' = 'invalid_values');
  r := pg_temp.res(a, da2, cid, 'recreate_copy', jsonb_build_object('new_entity_id', copy));
  perform pg_temp.assert('ed_copy_created', r ->> 'status' = 'applied' and (r ->> 'copy_entity_id')::uuid = copy and r -> 'row' ->> 'id' = copy::text
     and r -> 'row' ->> 'title' = 'Late edit' and r -> 'row' ->> 'notes' = 'keep me' and r -> 'row' ->> 'priority' = 'high'
     and r -> 'row' ->> 'project_id' = p1::text and r -> 'row' ->> 'owner_id' = a::text and (r -> 'row' ->> 'version')::int = 1);
  perform pg_temp.assert('ed_original_stays_tombstoned', (select deleted_at is not null from public.tasks where id = t1));
  perform pg_temp.assert('ed_status_resolved_copy', (select status from public.sync_conflicts where id = cid) = 'resolved_copy');
  begin update public.tasks set deleted_at = null where id = t1; perform pg_temp.assert('ed_tombstone_cannot_be_reverted', false);
  exception when others then perform pg_temp.assert('ed_tombstone_cannot_be_reverted', sqlerrm like '%tombstones cannot be reverted%'); end;
  -- a copy under a tombstoned project is refused
  perform pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 20), 'create', null, '{"name":"Short lived"}');
  perform pg_temp.c(a, da1, 'task', t6, 'create', null, jsonb_build_object('project_id', pg_temp.u('e1000000', 20), 'title', 'In short lived'));
  perform pg_temp.c(a, da1, 'task', t6, 'delete', 1);
  r := pg_temp.c(a, da2, 'task', t6, 'update', 1, '{"title":"x"}');
  perform pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 20), 'delete', 1);
  perform pg_temp.assert('ed_copy_under_tombstoned_project_is_parent_invalid',
     pg_temp.res(a, da2, (r ->> 'conflict_id')::uuid, 'recreate_copy', jsonb_build_object('new_entity_id', pg_temp.u('e2000000', 98))) ->> 'error_code' = 'parent_invalid');

  ---------------------------------------------------------------- delete_edited and parent_has_live_children
  perform pg_temp.c(a, da1, 'task', t2, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Edited then deleted'));
  perform pg_temp.c(a, da1, 'task', t2, 'update', 1, '{"title":"Edited"}');                                   -- v2
  r := pg_temp.c(a, da2, 'task', t2, 'delete', 1);
  perform pg_temp.assert('de_conflict_kind', r -> 'conflict' ->> 'kind' = 'delete_edited');
  cid := (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('de_merged_not_allowed', pg_temp.res(a, da2, cid, 'resolved_merged', '{"title":"x"}') ->> 'error_code' = 'strategy_not_allowed');
  r := pg_temp.res(a, da2, cid, 'resolved_server');
  perform pg_temp.assert('de_server_cancels_the_delete', r ->> 'status' = 'applied' and (select deleted_at is null from public.tasks where id = t2));
  r := pg_temp.c(a, da2, 'task', t2, 'delete', 1);
  r := pg_temp.res(a, da2, (r ->> 'conflict_id')::uuid, 'resolved_client');
  perform pg_temp.assert('de_client_deletes_anyway', r ->> 'status' = 'applied' and r -> 'row' ->> 'deleted_at' is not null and (r ->> 'applied_version')::int = 3);

  perform pg_temp.c(a, da1, 'task', tp, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Parent'));
  perform pg_temp.c(a, da1, 'task', tc, 'create', null, jsonb_build_object('project_id', p1, 'parent_id', tp, 'title', 'Child'));
  r := pg_temp.c(a, da2, 'task', tp, 'delete', 1);
  perform pg_temp.assert('pl_conflict_kind', r -> 'conflict' ->> 'kind' = 'parent_has_live_children');
  cid := (r ->> 'conflict_id')::uuid;
  r := pg_temp.res(a, da2, cid, 'resolved_client');
  perform pg_temp.assert('pl_client_blocked_while_children_live', r ->> 'error_code' = 'parent_has_live_children' and (select status from public.sync_conflicts where id = cid) = 'open'
     and (select deleted_at is null from public.tasks where id = tp));
  perform pg_temp.c(a, da1, 'task', tc, 'delete', 1);
  r := pg_temp.res(a, da2, cid, 'resolved_client');
  perform pg_temp.assert('pl_client_deletes_after_children_gone', r ->> 'status' = 'applied' and (select deleted_at is not null from public.tasks where id = tp));

  ---------------------------------------------------------------- exists
  r := pg_temp.c(a, da2, 'project', p1, 'create', null, '{"name":"Different"}');
  perform pg_temp.assert('ex_conflict_kind', r -> 'conflict' ->> 'kind' = 'exists');
  perform pg_temp.assert('ex_recreate_copy_not_allowed_on_a_live_entity', pg_temp.res(a, da2, (r ->> 'conflict_id')::uuid, 'recreate_copy',
     jsonb_build_object('new_entity_id', pg_temp.u('e2000000', 97))) ->> 'error_code' = 'strategy_not_allowed'
     and not exists (select 1 from public.projects where id = pg_temp.u('e2000000', 97)));
  r := pg_temp.res(a, da2, (r ->> 'conflict_id')::uuid, 'resolved_client');
  perform pg_temp.assert('ex_client_applies_the_create_values', r ->> 'status' = 'applied' and r -> 'row' ->> 'name' = 'Different');

  ---------------------------------------------------------------- unknown conflict, bad requests
  n0 := (select count(*) from public.sync_operations where user_id = a);
  r := pg_temp.resolve(a, da1, pg_temp.nid(), pg_temp.u('c1000000', 1), 'resolved_server');
  perform pg_temp.assert('unknown_conflict_not_found_and_not_recorded', r ->> 'error_code' = 'not_found' and (select count(*) from public.sync_operations where user_id = a) = n0);
  perform pg_temp.assert('bad_strategy_is_invalid_request', pg_temp.err(pg_temp.resolve(a, da1, pg_temp.nid(), cid, 'nonsense')) = 'NX005');
  perform pg_temp.assert('null_args_invalid_request', pg_temp.err(pg_temp.rpc(a, format('select public.nexora_resolve_conflict(null, %L, %L, ''resolved_server'')', pg_temp.nid(), cid))) = 'NX005');
  perform pg_temp.assert('non_object_values_invalid_request', pg_temp.err(pg_temp.rpc(a, format('select public.nexora_resolve_conflict(%L, %L, %L, ''resolved_merged'', ''[1]''::jsonb)', da1, pg_temp.nid(), cid))) = 'NX005');

  ---------------------------------------------------------------- authentication, devices, cross-user isolation
  perform pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 30), 'create', null, '{"name":"Auth host"}');
  perform pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 30), 'update', 1, '{"name":"Z1"}');
  r := pg_temp.c(a, da2, 'project', pg_temp.u('e1000000', 30), 'update', 1, '{"name":"Z2"}');
  perform pg_temp.assert('auth_setup_conflict', r ->> 'status' = 'conflict');
  cid2 := (r ->> 'conflict_id')::uuid; n0 := (select count(*) from public.sync_operations);
  perform pg_temp.assert('auth_signed_out', pg_temp.err(pg_temp.resolve(null, da2, pg_temp.nid(), cid2, 'resolved_server')) = '28000');
  perform pg_temp.assert('auth_anonymous_claim', pg_temp.err(pg_temp.resolve(anon_u, da2, pg_temp.nid(), cid2, 'resolved_server', null, true)) = '42501');
  perform pg_temp.assert('auth_deleted_user', pg_temp.err(pg_temp.resolve(gone, da2, pg_temp.nid(), cid2, 'resolved_server')) = '28000');
  perform pg_temp.assert('auth_foreign_device', pg_temp.err(pg_temp.resolve(a, db1, pg_temp.nid(), cid2, 'resolved_server')) = 'NX001');
  perform pg_temp.assert('auth_unknown_device', pg_temp.err(pg_temp.resolve(a, pg_temp.u('d0000000', 77), pg_temp.nid(), cid2, 'resolved_server')) = 'NX001');
  r := pg_temp.resolve(b, db1, pg_temp.nid(), cid2, 'resolved_server');
  perform pg_temp.assert('isolation_other_user_cannot_resolve', r ->> 'error_code' = 'not_found' and not (r::text like '%Z1%') and not (r::text like '%Z2%')
     and (select status from public.sync_conflicts where id = cid2) = 'open');
  r := pg_temp.resolve(b, db1, (select operation_id from public.sync_operations where user_id = a and op_type = 'resolve' limit 1), cid2, 'resolved_server');
  perform pg_temp.assert('isolation_other_users_operation_ids_independent', r ->> 'replayed' = 'false' and r ->> 'error_code' = 'not_found');
  perform pg_temp.assert('private_entry_point_same_identity_checks', pg_temp.err(pg_temp.rpc(null, format('select nexora_private.resolve_conflict(%L, %L, %L, ''resolved_server'')', da2, pg_temp.nid(), cid2))) = '28000');
  perform pg_temp.assert('anon_role_has_no_execute', pg_temp.err(pg_temp.rpc(null, format('select public.nexora_resolve_conflict(%L, %L, %L, ''resolved_server'')', da2, pg_temp.nid(), cid2), false, 'anon')) = '42501');
  perform pg_temp.assert('resolve_core_not_callable_by_clients', pg_temp.err(pg_temp.rpc(a, format('select nexora_private.resolve_core(%L, %L, %L, null, ''resolved_server'', null, ''h'')', a, da2, pg_temp.nid()))) = '42501');
  perform pg_temp.assert('revoked_device_cannot_resolve', (pg_temp.revoke(a, da1, drev) ->> 'revoked') = 'true'
     and pg_temp.err(pg_temp.resolve(a, drev, pg_temp.nid(), cid2, 'resolved_server')) = 'NX001');
  perform pg_temp.assert('failed_calls_recorded_nothing', (select count(*) from public.sync_operations) = n0);

  ---------------------------------------------------------------- immutable history
  perform pg_temp.res(a, da2, cid2, 'resolved_server');
  begin update public.sync_conflicts set status = 'open', resolved_at = null, resolution_source = null where id = cid2;
    perform pg_temp.assert('history_resolved_conflict_cannot_be_reopened', false);
  exception when others then perform pg_temp.assert('history_resolved_conflict_cannot_be_reopened', true); end;
  begin update public.sync_conflicts set client_value = '{}'::jsonb where id = cid2; perform pg_temp.assert('history_evidence_immutable', false);
  exception when others then perform pg_temp.assert('history_evidence_immutable', true); end;
  begin delete from public.sync_conflicts where id = cid2; perform pg_temp.assert('history_conflict_cannot_be_deleted', false);
  exception when others then perform pg_temp.assert('history_conflict_cannot_be_deleted', true); end;
  begin delete from public.sync_operations where op_type = 'resolve'; perform pg_temp.assert('history_resolution_operations_append_only', false);
  exception when others then perform pg_temp.assert('history_resolution_operations_append_only', true); end;
  perform pg_temp.assert('authenticated_cannot_write_conflicts_directly',
     pg_temp.err(pg_temp.rpc(a, format('update public.sync_conflicts set status = ''resolved_server'' where id = %L returning to_jsonb(1)', cid2))) is not null
     or (select status from public.sync_conflicts where id = cid2) = 'resolved_server');

  -- shape
  perform pg_temp.assert('s3_wrappers_invoker_private_definer',
    (select count(*) = 2 and bool_and(not prosecdef) and bool_and(proconfig = array['search_path=""']) from pg_proc
      where pronamespace = 'public'::regnamespace and proname in ('nexora_resolve_conflict','nexora_revoke_device'))
    and (select count(*) = 2 and bool_and(prosecdef) and bool_and(proconfig @> array['search_path=""','lock_timeout=5s']) and bool_and(pg_get_userbyid(proowner) = 'postgres')
         from pg_proc where pronamespace = 'nexora_private'::regnamespace and proname in ('resolve_conflict','revoke_device')));
  perform pg_temp.assert('resolve_core_has_empty_search_path_and_no_client_execute',
    (select proconfig @> array['search_path=""'] from pg_proc where pronamespace = 'nexora_private'::regnamespace and proname = 'resolve_core')
    and not has_function_privilege('authenticated', 'nexora_private.resolve_core(uuid,uuid,uuid,public.sync_conflicts,text,jsonb,text)', 'execute'));

  select count(*) into n0 from _r;
  raise notice 'assertions=%', n0;
end $$;
select 'S3 resolve suite: ' || count(*) || ' assertions passed' from _r;
rollback;
