-- S3 atomic tree delete suite (protocol extension: delete with patch {"tree": [{"id", "base_version"}, ...]}). Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1);
  da uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2); db1 uuid := pg_temp.u('d0000000', 3);
  p uuid := pg_temp.u('e1000000', 1); pb uuid := pg_temp.u('e1000000', 2);
  r uuid := pg_temp.u('e2000000', 1); c1 uuid := pg_temp.u('e2000000', 2); c2 uuid := pg_temp.u('e2000000', 3); g1 uuid := pg_temp.u('e2000000', 4);
  x uuid := pg_temp.u('e2000000', 5); late uuid := pg_temp.u('e2000000', 6); bt uuid := pg_temp.u('e2000000', 7);
  res jsonb; man jsonb; n int; live int; opid uuid; c public.sync_conflicts;
  function_dummy int;
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  perform pg_temp.reg(a, da); perform pg_temp.reg(a, da2); perform pg_temp.reg(b, db1);
  perform pg_temp.c(a, da, 'project', p, 'create', null, '{"name":"Tree host"}');
  perform pg_temp.c(a, da, 'task', r,  'create', null, jsonb_build_object('project_id', p, 'title', 'root'));
  perform pg_temp.c(a, da, 'task', c1, 'create', null, jsonb_build_object('project_id', p, 'parent_id', r, 'title', 'child 1'));
  perform pg_temp.c(a, da, 'task', c2, 'create', null, jsonb_build_object('project_id', p, 'parent_id', r, 'title', 'child 2'));
  perform pg_temp.c(a, da, 'task', g1, 'create', null, jsonb_build_object('project_id', p, 'parent_id', c1, 'title', 'grandchild'));
  perform pg_temp.c(a, da, 'task', x,  'create', null, jsonb_build_object('project_id', p, 'title', 'unrelated'));
  insert into public.projects(id, owner_id, name) values (pb, b, 'Bs project');
  insert into public.tasks(id, owner_id, project_id, title) values (bt, b, pb, 'Bs task');
  man := jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 1), jsonb_build_object('id', c2, 'base_version', 1),
                                                       jsonb_build_object('id', g1, 'base_version', 1)));
  live := (select count(*) from public.tasks where owner_id = a and deleted_at is null);

  ---------------------------------------------------------------- a manifest that misses a live descendant deletes nothing
  res := pg_temp.c(a, da, 'task', r, 'delete', 1, jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 1), jsonb_build_object('id', c2, 'base_version', 1))));
  perform pg_temp.assert('tm_missing_descendant_is_a_conflict', res ->> 'status' = 'conflict' and res -> 'conflict' ->> 'kind' = 'parent_has_live_children'
     and res -> 'conflict' -> 'server_value' = jsonb_build_object('live_children', jsonb_build_array(g1)));
  perform pg_temp.assert('tm_nothing_deleted_on_conflict', (select count(*) from public.tasks where owner_id = a and deleted_at is null) = live);
  perform pg_temp.assert('tm_conflict_evidence_lists_the_manifest', (select client_value ? 'tree' and kind = 'parent_has_live_children' and fields = array['deleted_at']
       from public.sync_conflicts where id = (res ->> 'conflict_id')::uuid));
  perform pg_temp.assert('tm_only_use_server_allowed_for_tree_conflicts',
     pg_temp.res(a, da, (res ->> 'conflict_id')::uuid, 'resolved_client') ->> 'error_code' = 'strategy_not_allowed');
  perform pg_temp.res(a, da, (res ->> 'conflict_id')::uuid, 'resolved_server');

  ---------------------------------------------------------------- a descendant edited after the manifest basis
  perform pg_temp.c(a, da2, 'task', c2, 'update', 1, '{"title":"child 2 edited elsewhere"}');                 -- c2 v2
  res := pg_temp.c(a, da, 'task', r, 'delete', 1, man);
  perform pg_temp.assert('tm_edited_descendant_is_delete_edited', res ->> 'status' = 'conflict' and res -> 'conflict' ->> 'kind' = 'delete_edited'
     and res -> 'conflict' -> 'server_value' -> 'edited' -> 0 ->> 'id' = c2::text);
  perform pg_temp.assert('tm_still_nothing_deleted', (select count(*) from public.tasks where owner_id = a and deleted_at is null) = live);
  perform pg_temp.res(a, da, (res ->> 'conflict_id')::uuid, 'resolved_server');
  man := jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 1), jsonb_build_object('id', c2, 'base_version', 2),
                                                       jsonb_build_object('id', g1, 'base_version', 1)));

  ---------------------------------------------------------------- a child created by another device after the manifest was built
  perform pg_temp.c(a, da2, 'task', late, 'create', null, jsonb_build_object('project_id', p, 'parent_id', c1, 'title', 'late child'));
  res := pg_temp.c(a, da, 'task', r, 'delete', 1, man);
  perform pg_temp.assert('tm_late_child_is_a_conflict', res -> 'conflict' ->> 'kind' = 'parent_has_live_children'
     and res -> 'conflict' -> 'server_value' -> 'live_children' = jsonb_build_array(late));
  perform pg_temp.res(a, da, (res ->> 'conflict_id')::uuid, 'resolved_server');
  perform pg_temp.c(a, da2, 'task', late, 'delete', 1);                                                       -- the other device deletes it itself
  live := (select count(*) from public.tasks where owner_id = a and deleted_at is null);

  ---------------------------------------------------------------- malformed or foreign manifests are rejected, nothing deleted
  perform pg_temp.assert('tm_lists_a_task_outside_the_subtree', pg_temp.c(a, da, 'task', r, 'delete', 1,
     jsonb_build_object('tree', man -> 'tree' || jsonb_build_array(jsonb_build_object('id', x, 'base_version', 1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_lists_the_root_itself', pg_temp.c(a, da, 'task', r, 'delete', 1,
     jsonb_build_object('tree', man -> 'tree' || jsonb_build_array(jsonb_build_object('id', r, 'base_version', 1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_duplicate_entries', pg_temp.c(a, da, 'task', r, 'delete', 1,
     jsonb_build_object('tree', man -> 'tree' || jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_foreign_id_in_manifest', pg_temp.c(a, da, 'task', r, 'delete', 1,
     jsonb_build_object('tree', man -> 'tree' || jsonb_build_array(jsonb_build_object('id', bt, 'base_version', 1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_entry_without_base', pg_temp.c(a, da, 'task', r, 'delete', 1, jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_entry_with_zero_base', pg_temp.c(a, da, 'task', r, 'delete', 1, jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 0)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_entry_with_bad_id', pg_temp.c(a, da, 'task', r, 'delete', 1, jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', 'x', 'base_version', 1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_entry_with_extra_key', pg_temp.c(a, da, 'task', r, 'delete', 1, jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 1, 'x', 1)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_tree_is_not_an_array', pg_temp.c(a, da, 'task', r, 'delete', 1, '{"tree":"x"}') ->> 'error_code' = 'invalid_op');
  perform pg_temp.assert('tm_extra_patch_key', pg_temp.c(a, da, 'task', r, 'delete', 1, '{"tree":[],"title":"x"}') ->> 'error_code' = 'invalid_op');
  perform pg_temp.assert('tm_more_than_1000_entries', pg_temp.c(a, da, 'task', r, 'delete', 1,
     jsonb_build_object('tree', (select jsonb_agg(jsonb_build_object('id', gen_random_uuid(), 'base_version', 1)) from generate_series(1, 1001)))) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_other_user_cannot_use_the_manifest', pg_temp.c(b, db1, 'task', r, 'delete', 1, man) ->> 'error_code' = 'not_found');
  perform pg_temp.assert('tm_other_users_root_with_my_ids', pg_temp.c(b, db1, 'task', bt, 'delete', 1, man) ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('tm_rejections_deleted_nothing', (select count(*) from public.tasks where owner_id = a and deleted_at is null) = live
     and (select deleted_at is null from public.tasks where id = bt));

  ---------------------------------------------------------------- failure injection: a failing descendant leaves the whole subtree live
  create function pg_temp.poison() returns trigger language plpgsql as $f$
  begin if new.deleted_at is not null and old.deleted_at is null and old.title = 'child 2 edited elsewhere' then raise exception 'injected failure' using errcode = '23514'; end if; return new; end $f$;
  create trigger zz_poison before update on public.tasks for each row execute function pg_temp.poison();
  res := pg_temp.c(a, da, 'task', r, 'delete', 1, man);
  perform pg_temp.assert('fi_class_23_failure_is_a_recorded_rejection', res ->> 'status' = 'rejected' and res ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('fi_no_partial_subtree_deletion', (select count(*) from public.tasks where owner_id = a and deleted_at is null) = live
     and (select deleted_at is null from public.tasks where id = r));
  drop trigger zz_poison on public.tasks;
  create or replace function pg_temp.poison() returns trigger language plpgsql as $f$
  begin if new.deleted_at is not null and old.deleted_at is null and old.title = 'child 2 edited elsewhere' then raise exception 'unexpected'; end if; return new; end $f$;
  create trigger zz_poison before update on public.tasks for each row execute function pg_temp.poison();
  res := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'task', r, 'delete', 1, man)));
  perform pg_temp.assert('fi_unexpected_failure_aborts_the_call', res ? 'error' and not (res ? 'results'));
  perform pg_temp.assert('fi_nothing_partial_after_abort', (select count(*) from public.tasks where owner_id = a and deleted_at is null) = live);
  drop trigger zz_poison on public.tasks;

  ---------------------------------------------------------------- success: atomic, authoritative, idempotent
  opid := pg_temp.nid();
  res := pg_temp.one(a, da, pg_temp.op(opid, 'task', r, 'delete', 1, man));
  perform pg_temp.assert('td_applied_atomically', res ->> 'status' = 'applied' and (res ->> 'tree_deleted')::int = 4 and res -> 'row' ->> 'deleted_at' is not null
     and (res ->> 'applied_version')::int = 2 and (res ->> 'version_before')::int = 1);
  perform pg_temp.assert('td_whole_subtree_tombstoned', not exists (select 1 from public.tasks where id in (r, c1, c2, g1) and deleted_at is null));
  perform pg_temp.assert('td_unrelated_and_other_users_untouched', (select deleted_at is null from public.tasks where id = x) and (select deleted_at is null from public.tasks where id = bt));
  perform pg_temp.assert('td_no_orphans', not exists (select 1 from public.tasks t where t.deleted_at is null and t.parent_id in (select id from public.tasks where deleted_at is not null)));
  perform pg_temp.assert('td_descendants_got_new_versions_and_sequence', (select bool_and(version = 2) from public.tasks where id in (c1, g1))
     and (select version = 3 from public.tasks where id = c2));
  perform pg_temp.assert('td_manifest_kept_for_audit', (select patch = man from public.sync_operations where user_id = a and operation_id = opid));
  res := pg_temp.one(a, da, pg_temp.op(opid, 'task', r, 'delete', 1, man));
  perform pg_temp.assert('td_replay_is_identical', res ->> 'replayed' = 'true' and (res ->> 'tree_deleted')::int = 4);
  perform pg_temp.assert('td_same_id_different_manifest_is_reuse', pg_temp.one(a, da, pg_temp.op(opid, 'task', r, 'delete', 1,
      jsonb_build_object('tree', jsonb_build_array(jsonb_build_object('id', c1, 'base_version', 1))))) ->> 'error_code' = 'operation_id_reuse');
  res := pg_temp.c(a, da, 'task', r, 'delete', 1, man);
  perform pg_temp.assert('td_already_tombstoned_root_is_a_noop', res ->> 'status' = 'applied' and not (res ? 'tree_deleted'));
  perform pg_temp.assert('td_tombstones_are_permanent', pg_temp.c(a, da, 'task', c1, 'update', 2, '{"title":"zombie"}') ->> 'status' = 'conflict');

  ---------------------------------------------------------------- an already-tombstoned descendant may be listed; project trees
  perform pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 5), 'create', null, '{"name":"Project tree"}');
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 20), 'create', null, jsonb_build_object('project_id', pg_temp.u('e1000000', 5), 'title', 'a'));
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 21), 'create', null, jsonb_build_object('project_id', pg_temp.u('e1000000', 5), 'parent_id', pg_temp.u('e2000000', 20), 'title', 'a.1'));
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 22), 'create', null, jsonb_build_object('project_id', pg_temp.u('e1000000', 5), 'title', 'b'));
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 22), 'delete', 1);                                    -- b already deleted singly
  res := pg_temp.c(a, da, 'project', pg_temp.u('e1000000', 5), 'delete', 1, jsonb_build_object('tree', jsonb_build_array(
     jsonb_build_object('id', pg_temp.u('e2000000', 20), 'base_version', 1), jsonb_build_object('id', pg_temp.u('e2000000', 21), 'base_version', 1),
     jsonb_build_object('id', pg_temp.u('e2000000', 22), 'base_version', 1))));
  perform pg_temp.assert('pj_project_tree_applied', res ->> 'status' = 'applied' and (res ->> 'tree_deleted')::int = 3);
  perform pg_temp.assert('pj_everything_tombstoned', not exists (select 1 from public.tasks where project_id = pg_temp.u('e1000000', 5) and deleted_at is null)
     and (select deleted_at is not null from public.projects where id = pg_temp.u('e1000000', 5)));

  ---------------------------------------------------------------- unchanged S2 behavior: a plain delete of a parent with live children is still a conflict
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 30), 'create', null, jsonb_build_object('project_id', p, 'title', 'plain parent'));
  perform pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 31), 'create', null, jsonb_build_object('project_id', p, 'parent_id', pg_temp.u('e2000000', 30), 'title', 'plain child'));
  perform pg_temp.assert('plain_delete_still_conflicts_with_live_children', pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 30), 'delete', 1) -> 'conflict' ->> 'kind' = 'parent_has_live_children');
  perform pg_temp.assert('plain_delete_with_empty_patch_still_valid', pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 31), 'delete', 1, '{}') ->> 'status' = 'applied');

  select count(*) into n from _r;
  raise notice 'assertions=%', n;
end $$;
select 'S3 tree delete suite: ' || count(*) || ' assertions passed' from _r;
rollback;
