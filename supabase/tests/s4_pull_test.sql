-- S4 incremental pull suite. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); b uuid := pg_temp.u('bbbbbbbb', 1); gone uuid := pg_temp.u('99999999', 1); anon_u uuid := pg_temp.u('aa000000', 1);
  da1 uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2); db1 uuid := pg_temp.u('d0000000', 3); drev uuid := pg_temp.u('d0000000', 4);
  p uuid := pg_temp.u('e1000000', 1); pb uuid := pg_temp.u('e1000000', 2);
  t1 uuid := pg_temp.u('e2000000', 1); t2 uuid := pg_temp.u('e2000000', 2);
  r jsonb; r2 jsonb; cur bigint; cur2 bigint; i int; n int; total int; seen uuid[] := '{}'; pages int; ids uuid[]; item jsonb; prev bigint; cid uuid; seqs bigint[];
begin
  perform pg_temp.mkuser(a); perform pg_temp.mkuser(b);
  insert into auth.users(id, is_anonymous) values (anon_u, true);
  perform pg_temp.reg(a, da1); perform pg_temp.reg(a, da2); perform pg_temp.reg(b, db1); perform pg_temp.reg(a, drev);

  ---------------------------------------------------------------- empty stream
  r := pg_temp.pull(a, da1, 0);
  perform pg_temp.assert('pl_empty_stream', r -> 'changes' = '[]'::jsonb and r -> 'conflicts' = '[]'::jsonb and (r ->> 'next_cursor')::bigint = 0 and r ->> 'has_more' = 'false');

  ---------------------------------------------------------------- first pull returns authoritative, server-owned rows
  perform pg_temp.c(a, da1, 'project', p, 'create', null, '{"name":"Alpha","sort_order":2}');
  perform pg_temp.c(a, da1, 'task', t1, 'create', null, jsonb_build_object('project_id', p, 'title', 'One', 'priority', 'high'));
  perform pg_temp.c(a, da1, 'task', t1, 'update', 1, '{"title":"One v2"}');
  perform pg_temp.c(a, da1, 'task', t2, 'create', null, jsonb_build_object('project_id', p, 'parent_id', t1, 'title', 'Two'));
  insert into public.projects(id, owner_id, name) values (pb, b, 'Bs project');
  r := pg_temp.pull(a, da2, 0);
  perform pg_temp.assert('pl_first_pull_has_all_current_rows', jsonb_array_length(r -> 'changes') = 3 and r ->> 'has_more' = 'false');
  perform pg_temp.assert('pl_one_row_per_entity_latest_version', (select count(*) from jsonb_array_elements(r -> 'changes') e where e -> 'row' ->> 'id' = t1::text) = 1
     and (select (e -> 'row' ->> 'version')::int from jsonb_array_elements(r -> 'changes') e where e -> 'row' ->> 'id' = t1::text) = 2);
  perform pg_temp.assert('pl_rows_carry_server_owned_fields', (select bool_and(e -> 'row' ? 'version' and e -> 'row' ? 'field_versions' and e -> 'row' ? 'change_seq' and e -> 'row' ->> 'owner_id' = a::text)
     from jsonb_array_elements(r -> 'changes') e)
     and (select e -> 'row' -> 'field_versions' ->> 'title' from jsonb_array_elements(r -> 'changes') e where e -> 'row' ->> 'id' = t1::text) = '2');
  perform pg_temp.assert('pl_changes_are_ordered_by_change_seq', (select array_agg((e -> 'row' ->> 'change_seq')::bigint) from jsonb_array_elements(r -> 'changes') e)
     = (select array_agg(x order by x) from (select (e -> 'row' ->> 'change_seq')::bigint x from jsonb_array_elements(r -> 'changes') e) s));
  perform pg_temp.assert('pl_next_cursor_is_the_last_change_seq', (r ->> 'next_cursor')::bigint = (select max((e -> 'row' ->> 'change_seq')::bigint) from jsonb_array_elements(r -> 'changes') e));
  perform pg_temp.assert('pl_no_other_users_rows', not (r::text like '%Bs project%') and not (r::text like '%' || pb::text || '%'));
  perform pg_temp.assert('pl_entity_types_labelled', (select array_agg(distinct e ->> 'entity_type' order by e ->> 'entity_type') from jsonb_array_elements(r -> 'changes') e) = array['project','task']);
  perform pg_temp.assert('pl_pull_records_last_pull_time', (select last_pull_at is not null from public.devices where id = da2));

  ---------------------------------------------------------------- idempotent repeated pull; incremental pull; non-contiguous cursors
  cur := (r ->> 'next_cursor')::bigint;
  perform pg_temp.assert('pl_repeat_pull_is_identical', pg_temp.pull(a, da2, 0) = r);
  r2 := pg_temp.pull(a, da2, cur);
  perform pg_temp.assert('pl_nothing_new_after_cursor', r2 -> 'changes' = '[]'::jsonb and (r2 ->> 'next_cursor')::bigint = cur);
  perform pg_temp.c(a, da1, 'task', t2, 'update', 1, '{"title":"Two v2"}');
  r2 := pg_temp.pull(a, da2, cur);
  perform pg_temp.assert('pl_incremental_pull_returns_only_the_change', jsonb_array_length(r2 -> 'changes') = 1 and r2 -> 'changes' -> 0 -> 'row' ->> 'id' = t2::text
     and (r2 ->> 'next_cursor')::bigint > cur);
  perform pg_temp.assert('pl_cursor_values_are_not_contiguous', (r2 ->> 'next_cursor')::bigint > cur + 1);
  perform pg_temp.assert('pl_pull_from_old_cursor_still_works', jsonb_array_length(pg_temp.pull(a, da2, 1) -> 'changes') = 3);

  ---------------------------------------------------------------- pagination
  for i in 1 .. 25 loop
    perform pg_temp.c(a, da1, 'task', pg_temp.u('e3000000', i), 'create', null, jsonb_build_object('project_id', p, 'title', 'bulk ' || i));
  end loop;
  total := (select count(*) from public.tasks where owner_id = a) + (select count(*) from public.projects where owner_id = a);
  cur := 0; pages := 0; ids := '{}'; prev := 0;
  loop
    r := pg_temp.pull(a, da2, cur, 10);
    pages := pages + 1;
    perform pg_temp.assert('pg_page_size_bound_' || pages, jsonb_array_length(r -> 'changes') <= 10 and jsonb_array_length(r -> 'changes') >= 1);
    for item in select * from jsonb_array_elements(r -> 'changes') loop
      perform pg_temp.assert('pg_no_duplicate_rows_' || (item -> 'row' ->> 'id'), not ((item -> 'row' ->> 'id')::uuid = any(ids)));
      perform pg_temp.assert('pg_strictly_increasing_' || (item -> 'row' ->> 'id'), (item -> 'row' ->> 'change_seq')::bigint > prev);
      ids := ids || (item -> 'row' ->> 'id')::uuid; prev := (item -> 'row' ->> 'change_seq')::bigint;
    end loop;
    cur := (r ->> 'next_cursor')::bigint;
    exit when r ->> 'has_more' = 'false';
    perform pg_temp.assert('pg_full_page_when_more_follows_' || pages, jsonb_array_length(r -> 'changes') = 10);
    exit when pages > 20;
  end loop;
  perform pg_temp.assert('pg_pages_cover_every_row_exactly_once', cardinality(ids) = total and pages = 3);
  perform pg_temp.assert('pg_limit_one_walks_one_by_one', (pg_temp.pull(a, da2, 0, 1) ->> 'has_more') = 'true' and jsonb_array_length(pg_temp.pull(a, da2, 0, 1) -> 'changes') = 1);
  perform pg_temp.assert('pg_limit_above_500_is_clamped', jsonb_array_length(pg_temp.pull(a, da2, 0, 100000) -> 'changes') = total);
  perform pg_temp.assert('pg_default_limit_applies', jsonb_array_length(pg_temp.pull(a, da2, 0, null) -> 'changes') = least(total, 200));
  perform pg_temp.assert('pg_limit_zero_rejected', pg_temp.err(pg_temp.pull(a, da2, 0, 0)) = 'NX005');
  perform pg_temp.assert('pg_negative_limit_rejected', pg_temp.err(pg_temp.pull(a, da2, 0, -5)) = 'NX005');

  ---------------------------------------------------------------- bounded response size
  for i in 1 .. 5 loop
    insert into public.tasks(id, owner_id, project_id, title, notes) values (pg_temp.u('e4000000', i), a, p, 'big ' || i, repeat('x', 400000));
  end loop;
  cur := pg_temp.maxseq(a) - 5 - 0;   -- just before the five big rows
  cur := (select min(change_seq) - 1 from public.tasks where id in (select pg_temp.u('e4000000', g) from generate_series(1, 5) g));
  n := 0; pages := 0; ids := '{}';
  loop
    r := pg_temp.pull(a, da2, cur, 500);
    pages := pages + 1;
    perform pg_temp.assert('sz_page_within_bound_or_single_item_' || pages, octet_length((r -> 'changes')::text) <= 1048576 + 600 or jsonb_array_length(r -> 'changes') = 1);
    perform pg_temp.assert('sz_progress_' || pages, jsonb_array_length(r -> 'changes') >= 1);
    n := n + jsonb_array_length(r -> 'changes');
    cur := (r ->> 'next_cursor')::bigint;
    exit when r ->> 'has_more' = 'false' or pages > 10;
  end loop;
  perform pg_temp.assert('sz_all_big_rows_delivered_across_pages', n = 5 and pages >= 2 and pages <= 5);

  ---------------------------------------------------------------- tombstones are delivered permanently
  perform pg_temp.c(a, da1, 'task', pg_temp.u('e3000000', 1), 'delete', 1);
  r := pg_temp.pull_all(a, da2, 0, 500);
  perform pg_temp.assert('tb_tombstone_in_the_stream', (select count(*) from jsonb_array_elements(r -> 'changes') e
       where e -> 'row' ->> 'id' = pg_temp.u('e3000000', 1)::text and e -> 'row' ->> 'deleted_at' is not null) = 1 and (r ->> 'pages')::int >= 2);
  for i in 1 .. 5 loop perform pg_temp.c(a, da1, 'task', pg_temp.u('e3000000', 2), 'update', i, jsonb_build_object('title', 'churn ' || i)); end loop;
  perform pg_temp.assert('tb_tombstone_still_delivered_after_more_activity', (select count(*) from jsonb_array_elements(pg_temp.pull_all(a, da2, 0, 500) -> 'changes') e
       where e -> 'row' ->> 'id' = pg_temp.u('e3000000', 1)::text and e -> 'row' ->> 'deleted_at' is not null) = 1);

  ---------------------------------------------------------------- conflicts travel in the same stream (and their resolution)
  cur := (pg_temp.pull_all(a, da2, 0, 500) ->> 'next_cursor')::bigint;
  perform pg_temp.c(a, da1, 'task', t1, 'update', 2, '{"notes":"theirs"}');
  r := pg_temp.c(a, da2, 'task', t1, 'update', 2, '{"notes":"mine"}');
  cid := (r ->> 'conflict_id')::uuid;
  r := pg_temp.pull(a, da1, cur, 500);
  perform pg_temp.assert('cf_open_conflict_in_the_stream', jsonb_array_length(r -> 'conflicts') = 1 and r -> 'conflicts' -> 0 ->> 'id' = cid::text and r -> 'conflicts' -> 0 ->> 'status' = 'open'
     and r -> 'conflicts' -> 0 -> 'server_value' = '{"notes":"theirs"}' and r -> 'conflicts' -> 0 -> 'client_value' = '{"notes":"mine"}');
  cur := (r ->> 'next_cursor')::bigint;
  perform pg_temp.res(a, da2, cid, 'resolved_server');
  r := pg_temp.pull(a, da1, cur, 500);
  perform pg_temp.assert('cf_resolution_is_a_new_change', jsonb_array_length(r -> 'conflicts') = 1 and r -> 'conflicts' -> 0 ->> 'status' = 'resolved_server'
     and r -> 'conflicts' -> 0 ->> 'resolution_source' = 'user' and (r -> 'conflicts' -> 0 ->> 'change_seq')::bigint > cur);
  perform pg_temp.assert('cf_other_user_never_sees_conflicts', pg_temp.pull(b, db1, 0) -> 'conflicts' = '[]'::jsonb);

  ---------------------------------------------------------------- same-user multi-device convergence
  perform pg_temp.c(a, da2, 'task', t2, 'update', 2, '{"title":"from device 2"}');
  r := pg_temp.pull_all(a, da1, 0, 500);
  perform pg_temp.assert('md_device_1_sees_device_2_write', (select e -> 'row' ->> 'title' from jsonb_array_elements(r -> 'changes') e where e -> 'row' ->> 'id' = t2::text) = 'from device 2');
  perform pg_temp.assert('md_both_devices_see_identical_state', pg_temp.pull_all(a, da1, 0, 500) -> 'changes' = pg_temp.pull_all(a, da2, 0, 500) -> 'changes');

  ---------------------------------------------------------------- cursor validation
  perform pg_temp.assert('cv_null_cursor', pg_temp.err(pg_temp.pull(a, da1, null)) = 'NX006');
  perform pg_temp.assert('cv_negative_cursor', pg_temp.err(pg_temp.pull(a, da1, -1)) = 'NX006');
  perform pg_temp.assert('cv_cursor_ahead_of_everything_issued', pg_temp.err(pg_temp.pull(a, da1, (select last_value from nexora_private.change_seq) + 1000000)) = 'NX006');
  perform pg_temp.assert('cv_cursor_at_the_high_water_mark_is_valid', pg_temp.pull(a, da1, (select last_value from nexora_private.change_seq)) ->> 'has_more' = 'false');
  perform pg_temp.assert('cv_other_users_activity_does_not_invalidate_a_cursor', pg_temp.err(pg_temp.pull(b, db1, pg_temp.maxseq(a))) is null);
  perform pg_temp.assert('cv_foreign_cursor_returns_only_own_rows', pg_temp.pull(b, db1, 0) -> 'changes' -> 0 -> 'row' ->> 'id' = pb::text and jsonb_array_length(pg_temp.pull(b, db1, 0) -> 'changes') = 1);

  ---------------------------------------------------------------- authentication, devices, grants
  perform pg_temp.assert('au_signed_out', pg_temp.err(pg_temp.pull(null, da1, 0)) = '28000');
  perform pg_temp.assert('au_anonymous_claim', pg_temp.err(pg_temp.pull(anon_u, da1, 0, 200, true)) = '42501');
  perform pg_temp.assert('au_deleted_user', pg_temp.err(pg_temp.pull(gone, da1, 0)) = '28000');
  perform pg_temp.assert('au_foreign_device', pg_temp.err(pg_temp.pull(a, db1, 0)) = 'NX001');
  perform pg_temp.assert('au_unknown_device', pg_temp.err(pg_temp.pull(a, pg_temp.u('d0000000', 77), 0)) = 'NX001' and pg_temp.err(pg_temp.pull(a, null, 0)) = 'NX005');
  perform pg_temp.assert('au_revoked_device', (pg_temp.revoke(a, da1, drev) ->> 'revoked') = 'true' and pg_temp.err(pg_temp.pull(a, drev, 0)) = 'NX001');
  perform pg_temp.assert('au_private_entry_point_same_checks', pg_temp.err(pg_temp.rpc(null, format('select nexora_private.pull(%L, 0)', da1))) = '28000');
  perform pg_temp.assert('au_anon_and_service_roles_have_no_execute',
     pg_temp.err(pg_temp.rpc(null, format('select public.nexora_sync_pull(%L, 0)', da1), false, 'anon')) = '42501'
     and pg_temp.err(pg_temp.rpc(null, format('select public.nexora_sync_pull(%L, 0)', da1), false, 'service_role')) = '42501');
  perform pg_temp.assert('au_shape', (select not prosecdef and proconfig = array['search_path=""'] from pg_proc where pronamespace = 'public'::regnamespace and proname = 'nexora_sync_pull')
     and (select prosecdef and proconfig @> array['search_path=""','lock_timeout=5s'] and pg_get_userbyid(proowner) = 'postgres' from pg_proc where pronamespace = 'nexora_private'::regnamespace and proname = 'pull'));
  perform pg_temp.assert('au_conflict_seq_trigger_enabled_always', (select tgenabled = 'A' from pg_trigger where tgname = 'sync_conflicts_seq'));

  select count(*) into n from _r;
  raise notice 'assertions=%', n;
end $$;
select 'S4 pull suite: ' || count(*) || ' assertions passed' from _r;
rollback;
