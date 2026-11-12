-- Regression suite for the standalone fix of nexora_private.guard_row() (UPDATE on public.projects).
-- Valid with or without S1. Rollback-only. Run after the Phase 2B migrations plus the fix.
begin;
create temp table _r(name text, ok boolean);
grant all on _r to public;
create function pg_temp.expect(label text, stmt text, code text default null, uid uuid default null, role_name text default 'authenticated')
returns void language plpgsql as $$
declare got text := 'NO_ERROR';
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text,''), true);
  execute format('set local role %I', role_name);
  begin execute stmt; exception when others then got := sqlstate; end;
  reset role;
  if (code is null and got <> 'NO_ERROR') or (code is not null and got <> code) then
    raise exception 'FAIL [%]: expected %, got %', label, coalesce(code,'NO_ERROR'), got;
  end if;
  insert into _r values (label, true);
end $$;
create function pg_temp.assert(label text, cond boolean) returns void language plpgsql as $$
begin if cond is not true then raise exception 'FAIL [%]', label; end if; insert into _r values (label, true); end $$;

do $$
declare
  a uuid := '00000000-0000-0000-0000-0000000000a9';
  b uuid := '00000000-0000-0000-0000-0000000000b9';
  p1 uuid := 'aaaaaaaa-0000-0000-0000-0000000000a9';
  p2 uuid := 'aaaaaaaa-0000-0000-0000-0000000000b9';
  t1 uuid := 'bbbbbbbb-0000-0000-0000-0000000000a9';
  p projects; d timestamptz; v bigint; s bigint;
begin
  insert into auth.users(id) values (a), (b);
  perform pg_temp.expect('A inserts project', format($f$insert into public.projects(id,owner_id,name) values (%L,%L,'P')$f$, p1, a), null, a);
  perform pg_temp.expect('B inserts project', format($f$insert into public.projects(id,owner_id,name) values (%L,%L,'PB')$f$, p2, b), null, b);

  -- the defect: UPDATE on projects used to raise 42703
  perform pg_temp.expect('project rename works', format($f$update public.projects set name='P renamed' where id=%L$f$, p1), null, a);
  perform pg_temp.expect('project several columns work', format($f$update public.projects set description='d', color='#fff', is_archived=true, sort_order=5 where id=%L$f$, p1), null, a);
  select * into p from public.projects where id = p1;
  perform pg_temp.assert('values stored', p.name='P renamed' and p.description='d' and p.color='#fff' and p.is_archived and p.sort_order=5);
  perform pg_temp.assert('version bumped by server per update', p.version = 3);
  perform pg_temp.assert('updated_at server set', p.updated_at >= now() - interval '1 minute');

  -- soft delete of a project
  perform pg_temp.expect('forged version ignored', format($f$update public.projects set version=99 where id=%L$f$, p1), null, a);
  select version into v from public.projects where id = p1;
  perform pg_temp.assert('forged version replaced by version+1', v = 4);
  perform pg_temp.expect('project soft delete', format($f$update public.projects set deleted_at='2000-01-01' where id=%L$f$, p1), null, a);
  select deleted_at, version into d, v from public.projects where id = p1;
  perform pg_temp.assert('tombstone time is server time', d > now() - interval '1 minute' and v = 5);
  perform pg_temp.expect('tombstone cannot be reverted', format($f$update public.projects set deleted_at=null where id=%L$f$, p1), '23514', a);
  perform pg_temp.expect('tombstoned project can still be renamed or archived (no new rule)', format($f$update public.projects set name='after' where id=%L$f$, p1), null, a);
  select deleted_at into d from public.projects where id = p1;
  perform pg_temp.assert('tombstone time unchanged by later update', d > now() - interval '1 minute');

  -- unchanged protections
  perform pg_temp.expect('owner reassignment rejected', format($f$update public.projects set owner_id=%L where id=%L$f$, b, p1), '42501', a);
  perform pg_temp.expect('id change rejected', format($f$update public.projects set id=gen_random_uuid() where id=%L$f$, p1), '42501', a);
  perform pg_temp.expect('B update statement runs but touches nothing', format($f$update public.projects set name='hijack' where id=%L$f$, p1), null, b);
  perform pg_temp.assert('A project name not hijacked', (select name from public.projects where id=p1) = 'after');
  perform pg_temp.expect('anon cannot update projects', format($f$update public.projects set name='x' where id=%L$f$, p1), '42501', null, 'anon');
  perform pg_temp.expect('client still cannot hard-delete projects', format($f$delete from public.projects where id=%L$f$, p2), '42501', b);

  -- tasks path unchanged
  perform pg_temp.expect('A inserts task', format($f$insert into public.tasks(id,project_id,owner_id,title) values (%L,%L,%L,'T')$f$, t1, p1, a), null, a);
  perform pg_temp.expect('task update works', format($f$update public.tasks set title='T2' where id=%L$f$, t1), null, a);
  perform pg_temp.assert('task version bumped', (select version from public.tasks where id=t1) = 2);
  perform pg_temp.expect('task project_id still immutable', format($f$update public.tasks set project_id=%L where id=%L$f$, p2, t1), '23514', a);
  perform pg_temp.expect('task owner still immutable', format($f$update public.tasks set owner_id=%L where id=%L$f$, b, t1), '42501', a);
  select change_seq into s from public.tasks where id = t1;
  perform pg_temp.assert('change_seq still assigned', s > 0);

  -- privileges unchanged by the fix
  perform pg_temp.assert('guard_row not executable by clients',
    not has_function_privilege('anon','nexora_private.guard_row()','execute')
    and not has_function_privilege('authenticated','nexora_private.guard_row()','execute'));
  perform pg_temp.assert('guard_row stays SECURITY DEFINER with empty search_path',
    (select prosecdef and proconfig = array['search_path=""'] from pg_proc where oid='nexora_private.guard_row()'::regprocedure));
  perform pg_temp.assert('no client DELETE grant on projects/tasks', not has_table_privilege('authenticated','public.projects','delete')
    and not has_table_privilege('authenticated','public.tasks','delete'));
end $$;

select count(*) as passed from _r;
rollback;
