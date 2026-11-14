-- Runs ONLY against a disposable database after proposed/completed_at_rule_option_a.sql is loaded (see tests/proposed/run_proposed.sh).
begin;
\ir ../s2_helpers.sql
do $$
declare a uuid := pg_temp.u('aaaaaaaa', 1); da uuid := pg_temp.u('d0000000', 1); p uuid := pg_temp.u('e1000000', 1);
        t uuid := pg_temp.u('e2000000', 1); r jsonb;
begin
  perform pg_temp.mkuser(a); perform pg_temp.reg(a, da);
  perform pg_temp.c(a, da, 'project', p, 'create', null, '{"name":"P"}');
  r := pg_temp.c(a, da, 'task', t, 'create', null, jsonb_build_object('project_id', p, 'title', 'T'));
  perform pg_temp.assert('open_task_without_completed_at_ok', r ->> 'status' = 'applied');
  r := pg_temp.c(a, da, 'task', t, 'update', 1, '{"status":"done"}');
  perform pg_temp.assert('done_without_completed_at_rejected', r ->> 'status' = 'rejected' and r ->> 'error_code' = 'invalid_patch');
  perform pg_temp.assert('rejection_changed_nothing', (select status from public.tasks where id = t) = 'open');
  r := pg_temp.c(a, da, 'task', t, 'update', 1, '{"status":"done","completed_at":"2026-11-12T10:00:00Z"}');
  perform pg_temp.assert('done_with_completed_at_applied', r ->> 'status' = 'applied' and r -> 'row' ->> 'status' = 'done');
  r := pg_temp.c(a, da, 'task', t, 'update', 2, '{"status":"in_progress"}');
  perform pg_temp.assert('leaving_done_without_clearing_completed_at_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da, 'task', t, 'update', 2, '{"status":"open","completed_at":null}');
  perform pg_temp.assert('reopen_clears_completed_at_applied', r ->> 'status' = 'applied' and r -> 'row' -> 'completed_at' = 'null'::jsonb);
  r := pg_temp.c(a, da, 'task', t, 'update', 3, '{"completed_at":"2026-11-12T10:00:00Z"}');
  perform pg_temp.assert('completed_at_on_open_task_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 2), 'create', null, jsonb_build_object('project_id', p, 'title', 'D', 'status', 'done'));
  perform pg_temp.assert('create_done_without_completed_at_rejected', r ->> 'error_code' = 'invalid_patch');
  r := pg_temp.c(a, da, 'task', pg_temp.u('e2000000', 3), 'create', null, jsonb_build_object('project_id', p, 'title', 'D', 'status', 'done', 'completed_at', '2026-11-12T10:00:00Z'));
  perform pg_temp.assert('create_done_with_completed_at_applied', r ->> 'status' = 'applied');
end $$;
select 'proposed completed_at rule (option A): ' || count(*) || ' assertions passed' from _r;
rollback;
