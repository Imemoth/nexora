-- Measures the protocol's worst legitimate cases on the local server and prints MEASURE lines. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); da uuid := pg_temp.u('d0000000', 1); da2 uuid := pg_temp.u('d0000000', 2);
  p uuid := pg_temp.u('e1000000', 1); root uuid := pg_temp.u('e2000000', 1);
  ops jsonb; r jsonb; t0 timestamptz; i int; cid uuid; note text; ids uuid[]; man jsonb; reqb int; cur bigint;
  big text := repeat('x', 200000);
begin
  perform pg_temp.mkuser(a); perform pg_temp.reg(a, da); perform pg_temp.reg(a, da2);
  perform pg_temp.c(a, da, 'project', p, 'create', null, '{"name":"Measure"}');

  ---------------------------------------------------------------- 1. a maximum-size push: 100 operations, ~896 KiB request
  note := repeat('n', 8700);
  ops := (select jsonb_agg(pg_temp.op(pg_temp.u('c1000000', g), 'task', pg_temp.u('e3000000', g), 'create', null,
            jsonb_build_object('project_id', p, 'title', 'M' || g, 'notes', note))) from generate_series(1, 100) g);
  reqb := octet_length(ops::text);
  t0 := clock_timestamp(); r := pg_temp.push(a, da, ops);
  perform pg_temp.assert('ml_max_push_applied', not (r ? 'error') and jsonb_array_length(r -> 'results') = 100);
  raise notice 'MEASURE push100 ms=% request_bytes=% response_bytes=%', round(extract(epoch from clock_timestamp() - t0) * 1000), reqb, octet_length(r::text);
  perform pg_temp.assert('ml_max_push_request_near_896KiB', reqb between 850000 and 1048576);

  ---------------------------------------------------------------- 2. a 500-row pull page
  cur := pg_temp.maxseq(a);
  insert into public.tasks(id, owner_id, project_id, title, notes)
    select pg_temp.u('e4000000', g), a, p, 'P' || g, repeat('p', 1500) from generate_series(1, 600) g;
  t0 := clock_timestamp(); r := pg_temp.pull(a, da2, cur, 500);
  perform pg_temp.assert('ml_pull500_is_a_full_page', not (r ? 'error') and jsonb_array_length(r -> 'changes') = 500 and (r ->> 'has_more')::boolean);
  raise notice 'MEASURE pull500 ms=% response_bytes=%', round(extract(epoch from clock_timestamp() - t0) * 1000), octet_length(r::text);

  ---------------------------------------------------------------- 3. resolve
  perform pg_temp.c(a, da, 'task', pg_temp.u('e3000000', 1), 'update', 1, '{"title":"A"}');
  r := pg_temp.push(a, da2, jsonb_build_array(pg_temp.op(pg_temp.nid(), 'task', pg_temp.u('e3000000', 1), 'update', 1, '{"title":"B"}')));
  cid := pg_temp.open_conflict(pg_temp.u('e3000000', 1));
  perform pg_temp.assert('ml_conflict_exists', cid is not null);
  t0 := clock_timestamp(); r := pg_temp.resolve(a, da2, pg_temp.nid(), cid, 'resolved_server');
  perform pg_temp.assert('ml_resolve_ok', not (r ? 'error'));
  raise notice 'MEASURE resolve ms=%', round(extract(epoch from clock_timestamp() - t0) * 1000);

  ---------------------------------------------------------------- 4. a 1000-descendant tree delete (binary heap shape, depth ~10)
  insert into public.tasks(id, owner_id, project_id, parent_id, title) values (root, a, p, null, 'tree root');
  for i in 1 .. 1000 loop
    insert into public.tasks(id, owner_id, project_id, parent_id, title)
      values (pg_temp.u('e5000000', i), a, p, case when i / 2 = 0 then root else pg_temp.u('e5000000', i / 2) end, 'N' || i);
  end loop;
  man := jsonb_build_object('tree', (select jsonb_agg(jsonb_build_object('id', pg_temp.u('e5000000', g), 'base_version', 1)) from generate_series(1, 1000) g));
  t0 := clock_timestamp(); r := pg_temp.c(a, da, 'task', root, 'delete', 1, man);
  perform pg_temp.assert('ml_tree1000_applied', r ->> 'status' = 'applied');
  perform pg_temp.assert('ml_tree1000_deleted_all', (select count(*) from public.tasks where owner_id = a and title like 'N%' and deleted_at is not null and id = any (select pg_temp.u('e5000000', g) from generate_series(1, 1000) g)) = 1000);
  raise notice 'MEASURE tree1000 ms=% request_bytes=%', round(extract(epoch from clock_timestamp() - t0) * 1000), octet_length(man::text);

  ---------------------------------------------------------------- 5. the largest accepted push response: ten echoed ~200 KiB rows
  ids := array(select pg_temp.u('e6000000', g) from generate_series(1, 10) g);
  insert into public.tasks(id, owner_id, project_id, title, notes) select x, a, p, 'B', big from unnest(ids) x;
  ops := (select jsonb_agg(pg_temp.op(pg_temp.nid(), 'task', x, 'update', 1, '{"title":"big"}')) from unnest(ids) x);
  t0 := clock_timestamp(); r := pg_temp.push(a, da, ops);
  perform pg_temp.assert('ml_largest_response_accepted', not (r ? 'error') and jsonb_array_length(r -> 'results') = 10);
  raise notice 'MEASURE push_largest_response ms=% response_bytes=%', round(extract(epoch from clock_timestamp() - t0) * 1000), octet_length(r::text);
  perform pg_temp.assert('ml_largest_response_below_the_bound', octet_length(r::text) < 2097152);
end $$;
select count(*) as passed from _r;
rollback;
