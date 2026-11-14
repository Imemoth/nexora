-- S2 apply semantics suite (create, update, delete, conflicts, spoofing, authorization). Rollback-only.
begin;
\ir s2_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da1 uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2); db1 uuid := pg_temp.u('d0000000', 3);
  p1 uuid := pg_temp.u('e1000000', 1); p2 uuid := pg_temp.u('e1000000', 2); pb uuid := pg_temp.u('e1000000', 3);
  pdel uuid := pg_temp.u('e1000000', 4); pcont uuid := pg_temp.u('e1000000', 5);
  t1 uuid := pg_temp.u('e2000000', 1); t2 uuid := pg_temp.u('e2000000', 2);
  r jsonb; r2 jsonb; k text; x uuid; c record; n0 bigint;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  perform pg_temp.reg(a, da1); perform pg_temp.reg(a, da2); perform pg_temp.reg(b, db1);
  insert into public.projects(id, owner_id, name) values (pb, b, 'Bs project');

  ---------------------------------------------------------------- create
  r := pg_temp.c(a, da1, 'project', p1, 'create', null, '{"name":"Alpha","sort_order":3}');
  perform pg_temp.assert('create_project_applied', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 1 and r ->> 'replayed' = 'false');
  perform pg_temp.assert('create_row_is_authoritative', r -> 'row' ->> 'name' = 'Alpha' and (r -> 'row' ->> 'sort_order')::int = 3
     and (r -> 'row' ->> 'version')::int = 1 and r -> 'row' ->> 'owner_id' = a::text and r -> 'row' -> 'field_versions' = '{}'::jsonb);
  perform pg_temp.assert('create_recorded_once_with_final_result',
    (select count(*) from public.sync_operations where user_id = a and entity_id = p1 and status = 'applied' and applied_version = 1 and base_version is null) = 1);
  r := pg_temp.c(a, da1, 'project', p2, 'create', 0, '{"name":"Beta"}');
  perform pg_temp.assert('create_accepts_base_version_zero_and_stores_null', r ->> 'status' = 'applied'
     and (select base_version from public.sync_operations where user_id = a and entity_id = p2) is null);
  r := pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 90), 'create', 3, '{"name":"X"}');
  perform pg_temp.assert('create_with_nonzero_base_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_op');
  r := pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 91), 'create', null, '{"description":"no name"}');
  perform pg_temp.assert('create_without_required_field_rejected', r ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('rejected_create_made_no_entity', not exists (select 1 from public.projects where id in (pg_temp.u('e1000000', 90), pg_temp.u('e1000000', 91))));

  r := pg_temp.c(a, da1, 'task', t1, 'create', null, jsonb_build_object('project_id', p1, 'title', 'Task one', 'priority', 'high'));
  perform pg_temp.assert('create_task_applied', r ->> 'status' = 'applied' and r -> 'row' ->> 'priority' = 'high' and r -> 'row' ->> 'status' = 'open');
  r := pg_temp.c(a, da1, 'task', t2, 'create', null, jsonb_build_object('project_id', p1, 'parent_id', t1, 'title', 'Child'));
  perform pg_temp.assert('create_child_task_applied', r ->> 'status' = 'applied' and r -> 'row' ->> 'parent_id' = t1::text);

  r := pg_temp.c(a, da1, 'project', p1, 'create', null, '{"name":"Alpha"}');
  perform pg_temp.assert('create_existing_identical_is_applied_noop', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 1
     and (select version from public.projects where id = p1) = 1);
  r := pg_temp.c(a, da1, 'project', p1, 'create', null, '{"name":"Gamma"}');
  perform pg_temp.assert('create_existing_different_is_exists_conflict', r ->> 'status' = 'conflict' and r ->> 'conflict_id' is not null);
  select * into c from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('exists_conflict_preserves_both_values', c.kind = 'exists' and c.status = 'open' and c.fields = array['name']
     and c.server_value = '{"name":"Alpha"}'::jsonb and c.client_value = '{"name":"Gamma"}'::jsonb and c.user_id = a);
  perform pg_temp.assert('exists_conflict_changed_nothing', (select name from public.projects where id = p1) = 'Alpha');
  r := pg_temp.c(a, da1, 'project', pb, 'create', null, '{"name":"Steal"}');
  perform pg_temp.assert('create_over_foreign_id_rejected_not_found', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'not_found');
  perform pg_temp.assert('foreign_entity_untouched', (select name from public.projects where id = pb) = 'Bs project');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 91), 'create', null, jsonb_build_object('project_id', pb, 'title', 'in foreign project'));
  perform pg_temp.assert('create_task_in_foreign_project_rejected', r ->> 'error_code' = 'not_found');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 92), 'create', null, jsonb_build_object('project_id', p1, 'parent_id', pg_temp.u('e2000000', 999), 'title', 'x'));
  perform pg_temp.assert('create_task_with_unknown_parent_rejected', r ->> 'error_code' = 'parent_invalid');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 93), 'create', null, jsonb_build_object('project_id', p2, 'parent_id', t1, 'title', 'cross-project parent'));
  perform pg_temp.assert('create_task_with_cross_project_parent_rejected', r ->> 'error_code' = 'parent_invalid');
  insert into public.tasks(id, project_id, owner_id, title) values (pg_temp.u('e2000000', 50), pb, b, 'Bs task');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 94), 'create', null, jsonb_build_object('project_id', p1, 'parent_id', pg_temp.u('e2000000', 50), 'title', 'foreign parent'));
  perform pg_temp.assert('create_task_with_foreign_parent_rejected', r ->> 'error_code' = 'parent_invalid');
  insert into public.projects(id, owner_id, name, deleted_at) values (pdel, a, 'Dead', now());
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 95), 'create', null, jsonb_build_object('project_id', pdel, 'title', 'in dead project'));
  perform pg_temp.assert('create_task_in_tombstoned_project_rejected', r ->> 'error_code' = 'parent_invalid');
  insert into public.tasks(id, project_id, owner_id, title, deleted_at) values (pg_temp.u('e2000000', 51), p1, a, 'Dead task', now());
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 96), 'create', null, jsonb_build_object('project_id', p1, 'parent_id', pg_temp.u('e2000000', 51), 'title', 'under dead parent'));
  perform pg_temp.assert('create_task_under_tombstoned_parent_rejected', r ->> 'error_code' = 'parent_invalid');
  r := pg_temp.c(a, da1, 'project', pdel, 'create', null, '{"name":"Dead"}');
  perform pg_temp.assert('create_over_tombstoned_entity_is_exists_conflict', r ->> 'status' = 'conflict'
     and (select kind from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid) = 'exists');

  ---------------------------------------------------------------- authorization and spoofing
  foreach k in array array['owner_id','user_id','version','field_versions','change_seq','created_at','updated_at','deleted_at','id','project_id','nope'] loop
    r := pg_temp.c(a, da1, 'task', t1, 'update', 1, jsonb_build_object(k, 'x'));
    perform pg_temp.assert('patch_key_rejected: ' || k, r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch');
  end loop;
  perform pg_temp.assert('spoof_attempts_changed_nothing', (select version from public.tasks where id = t1) = 1);
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, jsonb_build_object('owner_id', b));
  perform pg_temp.assert('forged_owner_id_rejected', r ->> 'error_code' = 'invalid_patch' and (select owner_id from public.tasks where id = t1) = a);
  r := pg_temp.c(a, da1, 'project', pb, 'update', 1, '{"name":"mine now"}');
  r2 := pg_temp.c(a, da1, 'project', pg_temp.u('e1000000', 777), 'update', 1, '{"name":"mine now"}');
  perform pg_temp.assert('foreign_entity_same_response_as_missing', r ->> 'error_code' = 'not_found' and (r - 'operation_id') = (r2 - 'operation_id'));
  perform pg_temp.assert('foreign_entity_not_modified', (select name from public.projects where id = pb) = 'Bs project');
  r := pg_temp.c(a, da1, 'project', pb, 'delete', 1);
  perform pg_temp.assert('delete_of_foreign_entity_rejected', r ->> 'error_code' = 'not_found' and (select deleted_at from public.projects where id = pb) is null);
  r := pg_temp.c(b, db1, 'project', p1, 'update', 1, '{"name":"B takes A project"}');
  perform pg_temp.assert('other_user_cannot_update_my_entity', r ->> 'error_code' = 'not_found' and (select name from public.projects where id = p1) = 'Alpha');
  -- values and types
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"sort_order":"abc"}');
  perform pg_temp.assert('wrong_json_type_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"title":null}');
  perform pg_temp.assert('null_for_not_null_column_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"status":"bogus"}');
  perform pg_temp.assert('invalid_status_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"due_date":"not-a-date"}');
  perform pg_temp.assert('invalid_date_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, jsonb_build_object('title', repeat('x', 201)));
  perform pg_temp.assert('title_over_200_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"title":"   "}');
  perform pg_temp.assert('blank_title_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, jsonb_build_object('parent_id', t1));
  perform pg_temp.assert('self_parent_rejected', r ->> 'error_code' = 'parent_invalid');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, jsonb_build_object('parent_id', t2));
  perform pg_temp.assert('parent_cycle_rejected', r ->> 'error_code' = 'parent_invalid');
  perform pg_temp.assert('rejected_updates_changed_nothing', (select version from public.tasks where id = t1) = 1
     and (select title from public.tasks where id = t1) = 'Task one');
  r := pg_temp.c(a, da1, 'task', t1, 'update', null, '{"title":"x"}');
  perform pg_temp.assert('update_without_base_rejected', r ->> 'error_code' = 'invalid_op');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 0, '{"title":"x"}');
  perform pg_temp.assert('update_with_base_zero_rejected', r ->> 'error_code' = 'invalid_op');
  r := pg_temp.c(a, da1, 'task', t1, 'update', 99, '{"title":"x"}');
  perform pg_temp.assert('update_with_base_ahead_of_server_rejected', r ->> 'error_code' = 'invalid_op');
  r := pg_temp.one(a, da1, jsonb_build_object('operation_id', pg_temp.nid(), 'entity_type', 'task', 'entity_id', t1, 'op_type', 'update', 'base_version', '1', 'patch', '{"title":"x"}'::jsonb));
  perform pg_temp.assert('base_version_as_string_rejected', r ->> 'error_code' = 'invalid_op');
  r := pg_temp.one(a, da1, jsonb_build_object('operation_id', pg_temp.nid(), 'entity_type', 'task', 'entity_id', t1, 'op_type', 'update', 'base_version', 1.5, 'patch', '{"title":"x"}'::jsonb));
  perform pg_temp.assert('fractional_base_version_rejected', r ->> 'error_code' = 'invalid_op');

  ---------------------------------------------------------------- update and field-level conflicts
  r := pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"title":"Renamed"}');
  perform pg_temp.assert('update_applied_with_server_version', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 2
     and r -> 'row' ->> 'title' = 'Renamed' and r -> 'row' -> 'field_versions' = '{"title":2}'::jsonb);
  r := pg_temp.c(a, da2, 'task', t1, 'update', 1, '{"notes":"from device 2"}');
  perform pg_temp.assert('different_fields_merge', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 3
     and r -> 'row' ->> 'title' = 'Renamed' and r -> 'row' ->> 'notes' = 'from device 2'
     and r -> 'row' -> 'field_versions' = '{"title":2,"notes":3}'::jsonb);
  r := pg_temp.c(a, da2, 'task', t1, 'update', 1, '{"title":"Renamed"}');
  perform pg_temp.assert('same_value_stale_edit_is_noop_applied', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 3
     and (select version from public.tasks where id = t1) = 3);
  r := pg_temp.c(a, da2, 'task', t1, 'update', 1, '{}');
  perform pg_temp.assert('empty_patch_is_noop', r ->> 'status' = 'applied' and (select version from public.tasks where id = t1) = 3);
  r := pg_temp.c(a, da2, 'task', t1, 'update', 3, '{"priority":"low"}');
  perform pg_temp.assert('fresh_base_applies', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 4);
  r := pg_temp.c(a, da2, 'task', t1, 'update', 2, '{"priority":"high","notes":"other"}');
  perform pg_temp.assert('multi_field_partial_overlap_conflicts_atomically', r ->> 'status' = 'conflict');
  select * into c from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('conflict_lists_only_the_conflicting_fields', c.kind = 'field' and c.status = 'open' and c.fields = array['notes','priority'] and c.base_version = 2 and c.server_version = 4);
  perform pg_temp.assert('conflict_preserves_server_and_client_values',
    c.server_value = '{"notes":"from device 2","priority":"low"}'::jsonb and c.client_value = '{"priority":"high","notes":"other"}'::jsonb);
  perform pg_temp.assert('conflicting_operation_applied_nothing', (select version from public.tasks where id = t1) = 4
     and (select notes from public.tasks where id = t1) = 'from device 2' and r -> 'row' ->> 'version' = '4');
  r := pg_temp.c(a, da2, 'task', t1, 'update', 4, '{"title":"blocked"}');
  perform pg_temp.assert('later_operation_blocked_by_open_conflict', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'blocked_by_conflict');
  perform pg_temp.assert('blocked_operation_is_recorded', exists (select 1 from public.sync_operations where operation_id = (r ->> 'operation_id')::uuid and status = 'rejected'));
  perform pg_temp.assert('conflict_not_visible_to_other_user', (select count(*) from public.sync_conflicts where user_id = b) = 0);

  -- explicit NULL versus absent
  insert into public.tasks(id, project_id, owner_id, title, due_date, notes, priority) values (pg_temp.u('e2000000', 10), p1, a, 'Dated', '2026-03-01', 'keep', 'medium');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 10), 'update', 1, '{"due_date":null}');
  perform pg_temp.assert('explicit_null_clears_nullable_column', r ->> 'status' = 'applied' and r -> 'row' -> 'due_date' = 'null'::jsonb and r -> 'row' ->> 'notes' = 'keep');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 10), 'update', 2, '{"title":"Dated again"}');
  perform pg_temp.assert('absent_fields_are_untouched', r -> 'row' ->> 'notes' = 'keep' and r -> 'row' ->> 'priority' = 'medium' and r -> 'row' -> 'due_date' = 'null'::jsonb);
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 10), 'update', 3, '{"due_date":"2026-04-02","completed_at":"2026-04-02T10:00:00Z"}');
  perform pg_temp.assert('characterization: completed_at is an ordinary field (rule pending owner decision)', r ->> 'status' = 'applied' and r -> 'row' ->> 'due_date' = '2026-04-02');

  -- sort_order policy (D-O): server wins, losing value preserved and auditable
  insert into public.tasks(id, project_id, owner_id, title, sort_order) values (pg_temp.u('e2000000', 11), p1, a, 'Sorted', 0);
  update public.tasks set sort_order = 5 where id = pg_temp.u('e2000000', 11);
  r := pg_temp.c(a, da2, 'task', pg_temp.u('e2000000', 11), 'update', 1, '{"sort_order":9}');
  perform pg_temp.assert('sort_order_conflict_auto_resolved_server_wins', r ->> 'status' = 'applied' and r ->> 'auto_resolved' = 'true'
     and (r -> 'row' ->> 'sort_order')::int = 5 and (r ->> 'applied_version')::int = 2 and r ->> 'conflict_id' is not null);
  select * into c from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('auto_resolution_is_auditable_and_preserves_both_values',
    c.status = 'resolved_server' and c.resolution_source = 'auto_policy' and c.resolution_policy = 'sort_order_server_wins'
    and c.resolved_at is not null and c.server_value = '{"sort_order":5}'::jsonb and c.client_value = '{"sort_order":9}'::jsonb and c.fields = array['sort_order']);
  perform pg_temp.assert('auto_resolved_conflict_does_not_block', (pg_temp.c(a, da2, 'task', pg_temp.u('e2000000', 11), 'update', 2, '{"notes":"ok"}')) ->> 'status' = 'applied');
  insert into public.tasks(id, project_id, owner_id, title, sort_order) values (pg_temp.u('e2000000', 12), p1, a, 'Mixed', 0);
  update public.tasks set sort_order = 5 where id = pg_temp.u('e2000000', 12);
  r := pg_temp.c(a, da2, 'task', pg_temp.u('e2000000', 12), 'update', 1, '{"title":"Mixed new","sort_order":9}');
  perform pg_temp.assert('sort_order_conflict_does_not_block_other_fields', r ->> 'status' = 'applied' and r -> 'row' ->> 'title' = 'Mixed new'
     and (r -> 'row' ->> 'sort_order')::int = 5 and r ->> 'auto_resolved' = 'true');
  insert into public.tasks(id, project_id, owner_id, title, sort_order) values (pg_temp.u('e2000000', 13), p1, a, 'Real', 0);
  update public.tasks set sort_order = 5 where id = pg_temp.u('e2000000', 13);
  update public.tasks set title = 'Server title' where id = pg_temp.u('e2000000', 13);
  r := pg_temp.c(a, da2, 'task', pg_temp.u('e2000000', 13), 'update', 1, '{"title":"Client title","sort_order":9}');
  perform pg_temp.assert('real_conflict_with_sort_order_conflicts_whole_operation', r ->> 'status' = 'conflict');
  select * into c from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid;
  perform pg_temp.assert('mixed_conflict_is_open_with_all_values_preserved', c.status = 'open' and c.resolution_source is null and c.fields = array['sort_order','title']
     and (select title from public.tasks where id = pg_temp.u('e2000000', 13)) = 'Server title' and c.client_value = '{"title":"Client title","sort_order":9}'::jsonb);

  ---------------------------------------------------------------- delete and tombstones
  r := pg_temp.c(a, da1, 'task', t2, 'delete', 1);
  perform pg_temp.assert('delete_tombstones_with_server_time', r ->> 'status' = 'applied' and (r ->> 'applied_version')::int = 2
     and r -> 'row' ->> 'deleted_at' is not null and (select deleted_at from public.tasks where id = t2) > now() - interval '1 minute');
  r2 := pg_temp.c(a, da1, 'task', t2, 'delete', 2);
  perform pg_temp.assert('second_delete_is_idempotent_noop', r2 ->> 'status' = 'applied' and (r2 ->> 'applied_version')::int = 2);
  r := pg_temp.c(a, da1, 'task', t2, 'update', 2, '{"title":"zombie"}');
  perform pg_temp.assert('update_after_delete_is_edit_deleted_conflict', r ->> 'status' = 'conflict'
     and (select kind from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid) = 'edit_deleted');
  perform pg_temp.assert('tombstone_not_resurrected', (select deleted_at from public.tasks where id = t2) is not null and (select title from public.tasks where id = t2) = 'Child');
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 10), 'update', 4, '{"deleted_at":null}');
  perform pg_temp.assert('deleted_at_is_not_patchable', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da1, 'task', t1, 'delete', 4);
  perform pg_temp.assert('delete_blocked_by_open_conflict_on_entity', r ->> 'error_code' = 'blocked_by_conflict');
  -- parent with live children, and delete after a later edit
  insert into public.projects(id, owner_id, name) values (pcont, a, 'Container');
  insert into public.tasks(id, project_id, owner_id, title) values (pg_temp.u('e2000000', 20), pcont, a, 'Kid');
  r := pg_temp.c(a, da1, 'project', pcont, 'delete', 1);
  perform pg_temp.assert('delete_project_with_live_tasks_conflicts', r ->> 'status' = 'conflict'
     and (select kind from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid) = 'parent_has_live_children'
     and (select deleted_at from public.projects where id = pcont) is null);
  insert into public.tasks(id, project_id, owner_id, title) values (pg_temp.u('e2000000', 21), pcont, a, 'Parent'), (pg_temp.u('e2000000', 22), pcont, a, 'Edited later');
  update public.tasks set parent_id = pg_temp.u('e2000000', 21) where id = pg_temp.u('e2000000', 22);
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 21), 'delete', 1);
  perform pg_temp.assert('delete_task_with_live_children_conflicts', r ->> 'status' = 'conflict'
     and (select kind from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid) = 'parent_has_live_children');
  insert into public.tasks(id, project_id, owner_id, title) values (pg_temp.u('e2000000', 23), pcont, a, 'Leaf');
  update public.tasks set title = 'Leaf edited elsewhere' where id = pg_temp.u('e2000000', 23);
  r := pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 23), 'delete', 1);
  perform pg_temp.assert('delete_after_a_later_edit_conflicts', r ->> 'status' = 'conflict'
     and (select kind from public.sync_conflicts where id = (r ->> 'conflict_id')::uuid) = 'delete_edited'
     and (select deleted_at from public.tasks where id = pg_temp.u('e2000000', 23)) is null);
  insert into public.tasks(id, project_id, owner_id, title) values (pg_temp.u('e2000000', 24), pcont, a, 'Clean leaf');
  perform pg_temp.assert('leaf_first_delete_applies', (pg_temp.c(a, da1, 'task', pg_temp.u('e2000000', 24), 'delete', 1)) ->> 'status' = 'applied');
  r := pg_temp.one(a, da1, jsonb_build_object('operation_id', pg_temp.nid(), 'entity_type', 'task', 'entity_id', pg_temp.u('e2000000', 24), 'op_type', 'delete', 'base_version', 2, 'patch', '{"title":"x"}'::jsonb));
  perform pg_temp.assert('delete_with_patch_rejected', r ->> 'error_code' = 'invalid_op');

  ---------------------------------------------------------------- recorded results and server-owned data
  perform pg_temp.assert('every_recorded_row_has_a_final_result', not exists (select 1 from public.sync_operations where user_id = a
     and (result is null or result ->> 'status' <> status or (result ->> 'operation_id')::uuid <> operation_id)));
  perform pg_temp.assert('applied_rows_carry_applied_version', not exists (select 1 from public.sync_operations where user_id = a and status = 'applied' and applied_version is null)
     and not exists (select 1 from public.sync_operations where user_id = a and status <> 'applied' and applied_version is not null));
  perform pg_temp.assert('server_seq_is_monotone_per_user', (select bool_and(server_seq > lag_seq) from (select server_seq, lag(server_seq) over (order by received_at, server_seq) lag_seq from public.sync_operations where user_id = a) q where lag_seq is not null));
  perform pg_temp.assert('other_users_operations_never_applied_anything', not exists (select 1 from public.sync_operations where user_id = b and status <> 'rejected'));
end $$;
select count(*) as passed from _r;
rollback;
