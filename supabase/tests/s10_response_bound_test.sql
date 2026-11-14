-- S10b: push response bound (2 MiB) -> NX004; single operation always answered. Rollback-only.
begin;
\ir s2_helpers.sql
\ir s34_helpers.sql
do $$
declare
  a uuid := pg_temp.u('aaaaaaaa', 1); da uuid := pg_temp.u('d0000000', 1);
  p uuid := pg_temp.u('e1000000', 1);
  r jsonb; i int; big text := repeat('x', 200000); ops jsonb := '[]'::jsonb; upd jsonb; sz int; n_before int; seq_before bigint;
begin
  perform pg_temp.mkuser(a); perform pg_temp.reg(a, da);
  perform pg_temp.c(a, da, 'project', p, 'create', null, '{"name":"P"}');

  ---------------------------------------------------------------- worst case: tiny request, huge response
  -- 100 tasks with ~200 KiB notes each (created four per push, within the 896 KiB request bound), then 100 tiny updates:
  -- the request is a few KiB, every applied result echoes its row (~200 KiB), response ~20 MB without the bound.
  for i in 1 .. 100 loop
    ops := ops || jsonb_build_array(pg_temp.op(pg_temp.u('c5000000', i), 'task', pg_temp.u('e5000000', i), 'create', null,
              jsonb_build_object('project_id', p, 'title', 'T' || i, 'notes', big)));
  end loop;
  for i in 0 .. 24 loop
    r := pg_temp.push(a, da, (select jsonb_agg(e) from (select e from jsonb_array_elements(ops) with ordinality x(e, n) where n > i * 4 and n <= i * 4 + 4 order by n) q));
    perform pg_temp.assert('rb_setup_chunk_' || i, not (r ? 'error') and jsonb_array_length(r -> 'results') = 4);
  end loop;
  perform pg_temp.assert('rb_setup_100_big_tasks', (select count(*) from public.tasks where owner_id = a and octet_length(notes) >= 200000) = 100);
  upd := '[]'::jsonb;
  for i in 1 .. 100 loop
    upd := upd || jsonb_build_array(pg_temp.op(pg_temp.u('c7000000', i), 'task', pg_temp.u('e5000000', i), 'update', 1, '{"title":"renamed"}'));
  end loop;
  perform pg_temp.assert('rb_request_is_tiny', octet_length(upd::text) < 65536);
  select count(*) into n_before from public.sync_operations where user_id = a;
  select coalesce(max(change_seq), 0) into seq_before from public.tasks;
  r := pg_temp.push(a, da, upd);
  perform pg_temp.assert('rb_oversized_response_is_refused_nx004', pg_temp.err(r) = 'NX004' and pg_temp.msg(r) = 'payload_too_large');
  perform pg_temp.assert('rb_nothing_recorded_after_refusal',
    (select count(*) from public.sync_operations where user_id = a) = n_before
    and (select coalesce(max(change_seq), 0) from public.tasks) = seq_before
    and not exists (select 1 from public.tasks where owner_id = a and title = 'renamed'));
  -- halving (what the client does) converges: 100 -> 50 -> 25 -> 12 -> 6 ... the first size under the bound is applied
  r := pg_temp.push(a, da, (select jsonb_agg(e) from (select e from jsonb_array_elements(upd) with ordinality x(e, n) where n <= 6 order by n) q));
  perform pg_temp.assert('rb_halved_batch_of_six_applies', not (r ? 'error') and jsonb_array_length(r -> 'results') = 6);
  raise notice 'MEASURE six echoed-200KiB-row push response bytes=%', octet_length(r::text);
  -- the refused 100-op batch, retried one operation at a time, is always answered
  r := pg_temp.push(a, da, jsonb_build_array(upd -> 50));
  perform pg_temp.assert('rb_single_op_always_answered', r -> 'results' -> 0 ->> 'status' = 'applied');
  -- a replay of the six applied ops (same ids) answers within the bound
  r := pg_temp.push(a, da, (select jsonb_agg(e) from (select e from jsonb_array_elements(upd) with ordinality x(e, n) where n <= 6 order by n) q));
  perform pg_temp.assert('rb_replay_of_applied_batch_below_bound_still_works', not (r ? 'error') and jsonb_array_length(r -> 'results') = 6);
  -- replaying the full 100 (six+one applied, rest new) is refused too and still records nothing
  select count(*) into n_before from public.sync_operations where user_id = a;
  r := pg_temp.push(a, da, upd);
  perform pg_temp.assert('rb_full_batch_still_refused_after_partial_progress', pg_temp.err(r) = 'NX004'
    and (select count(*) from public.sync_operations where user_id = a) = n_before);

  ---------------------------------------------------------------- a single create with a ~200 KiB note is accepted and answered
  r := pg_temp.push(a, da, jsonb_build_array(pg_temp.op(pg_temp.u('c8000000', 1), 'task', pg_temp.u('e8000000', 1), 'create', null,
        jsonb_build_object('project_id', p, 'title', 'S', 'notes', big))));
  sz := octet_length(r::text);
  perform pg_temp.assert('rb_single_large_operation_accepted', r -> 'results' -> 0 ->> 'status' = 'applied' and sz < 2097152);
  raise notice 'MEASURE single 200000-char-notes push response bytes=%', sz;

  ---------------------------------------------------------------- normal batch unaffected
  ops := '[]'::jsonb;
  for i in 1 .. 100 loop
    ops := ops || jsonb_build_array(pg_temp.op(pg_temp.u('c6000000', i), 'task', pg_temp.u('e6000000', i), 'create', null,
              jsonb_build_object('project_id', p, 'title', 'N' || i)));
  end loop;
  r := pg_temp.push(a, da, ops);
  perform pg_temp.assert('rb_normal_100_op_batch_unaffected', not (r ? 'error') and jsonb_array_length(r -> 'results') = 100);
  raise notice 'MEASURE normal 100-op push response bytes=%', octet_length(r::text);

  ---------------------------------------------------------------- the check lives in the DEFINER body and is a hard bound
  perform pg_temp.assert('rb_bound_constant_present_in_push',
    (select prosrc like '%2097152%' and prosrc like '%NX004%' from pg_proc where oid = 'nexora_private.push(uuid,jsonb)'::regprocedure));
end $$;
select count(*) as passed from _r;
rollback;
