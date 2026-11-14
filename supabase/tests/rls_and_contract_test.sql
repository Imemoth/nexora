-- Run after the three migrations. Raises on first failed assertion; always rolls back (no data kept).
-- Works unchanged on a local Postgres fixture and, wrapped by the caller in a rollback, on hosted.
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
create function pg_temp.count_as(stmt text, uid uuid, role_name text default 'authenticated') returns bigint
language plpgsql as $$
declare n bigint;
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text,''), true);
  execute format('set local role %I', role_name);
  execute stmt into n; reset role; return n;
end $$;
create function pg_temp.assert(label text, cond boolean) returns void language plpgsql as $$
begin if cond is not true then raise exception 'FAIL [%]', label; end if; insert into _r values (label, true); end $$;

do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000000a';
  b uuid := '00000000-0000-0000-0000-00000000000b';
  pa uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  pa2 uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  t1 uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  t2 uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  t3 uuid := 'bbbbbbbb-0000-0000-0000-000000000003';
  v1 bigint; v2 bigint; s1 bigint; s2 bigint; d timestamptz;
begin
  insert into auth.users(id) values (a), (b);
  -- A creates data (offline-created ids supplied by the client)
  perform pg_temp.expect('A inserts project', format($f$insert into public.projects(id,owner_id,name) values (%L,%L,'P')$f$, pa, a), null, a);
  perform pg_temp.expect('A inserts 2nd project', format($f$insert into public.projects(id,owner_id,name) values (%L,%L,'P2')$f$, pa2, a), null, a);
  perform pg_temp.expect('A inserts task', format($f$insert into public.tasks(id,project_id,owner_id,title) values (%L,%L,%L,'T1')$f$, t1, pa, a), null, a);
  perform pg_temp.expect('A inserts child', format($f$insert into public.tasks(id,project_id,owner_id,parent_id,title) values (%L,%L,%L,%L,'T2')$f$, t2, pa, a, t1), null, a);

  -- isolation
  perform pg_temp.assert('B sees no projects', pg_temp.count_as('select count(*) from public.projects', b) = 0);
  perform pg_temp.assert('B sees no tasks', pg_temp.count_as('select count(*) from public.tasks', b) = 0);
  perform pg_temp.assert('A sees own tasks', pg_temp.count_as('select count(*) from public.tasks', a) = 2);
  perform pg_temp.assert('B update affects 0 rows', pg_temp.count_as(format($f$with u as (update public.tasks set title='x' where id=%L returning 1) select count(*) from u$f$, t1), b) = 0);
  perform pg_temp.expect('B cannot insert task as owner A', format($f$insert into public.tasks(project_id,owner_id,title) values (%L,%L,'evil')$f$, pa, a), '42501', b);
  perform pg_temp.expect('B cannot insert into A project as itself', format($f$insert into public.tasks(project_id,owner_id,title) values (%L,%L,'evil')$f$, pa, b), '23503', b);
  perform pg_temp.expect('B cannot insert project owned by A', format($f$insert into public.projects(owner_id,name) values (%L,'evil')$f$, a), '42501', b);
  perform pg_temp.expect('A cannot reassign task owner to B', format($f$update public.tasks set owner_id=%L where id=%L$f$, b, t1), '42501', a);
  perform pg_temp.expect('A cannot reassign project owner to B', format($f$update public.projects set owner_id=%L where id=%L$f$, b, pa), '42501', a);

  -- anonymous
  perform pg_temp.expect('anon cannot select tasks', 'select * from public.tasks', '42501', null, 'anon');
  perform pg_temp.expect('anon cannot insert projects', format($f$insert into public.projects(owner_id,name) values (%L,'x')$f$, a), '42501', null, 'anon');
  perform pg_temp.expect('anon cannot read sync_operations', 'select * from public.sync_operations', '42501', null, 'anon');
  perform pg_temp.expect('anon cannot read profiles', 'select * from public.profiles', '42501', null, 'anon');

  -- no hard delete
  perform pg_temp.expect('A cannot hard-delete task', format($f$delete from public.tasks where id=%L$f$, t2), '42501', a);
  perform pg_temp.expect('A cannot hard-delete project', format($f$delete from public.projects where id=%L$f$, pa2), '42501', a);

  -- membership grants nothing
  insert into public.project_members(project_id,user_id,role) values (pa, b, 'editor');
  perform pg_temp.assert('member sees no project', pg_temp.count_as('select count(*) from public.projects', b) = 0);
  perform pg_temp.assert('member sees no tasks', pg_temp.count_as('select count(*) from public.tasks', b) = 0);
  perform pg_temp.expect('member cannot update task', format($f$update public.tasks set title='x' where id=%L$f$, t1), null, b);
  perform pg_temp.assert('member update changed nothing', (select title from public.tasks where id=t1) = 'T1');
  perform pg_temp.expect('client cannot read project_members', 'select * from public.project_members', '42501', a);
  perform pg_temp.expect('client cannot add member', format($f$insert into public.project_members values (%L,%L,'viewer')$f$, pa, b), '42501', a);

  -- versioning / server-controlled fields
  select version, change_seq into v1, s1 from public.tasks where id = t1;
  perform pg_temp.assert('insert version = 1', v1 = 1);
  perform pg_temp.expect('A updates with forged version', format($f$update public.tasks set title='T1b', version=99, change_seq=0 where id=%L$f$, t1), null, a);
  select version, change_seq into v2, s2 from public.tasks where id = t1;
  perform pg_temp.assert('version bumped by server only', v2 = 2);
  perform pg_temp.assert('change_seq strictly increases', s2 > s1);
  perform pg_temp.expect('task project_id immutable', format($f$update public.tasks set project_id=%L where id=%L$f$, pa2, t1), '23514', a);

  -- tombstones
  perform pg_temp.expect('A soft-deletes task', format($f$update public.tasks set deleted_at = '2000-01-01' where id=%L$f$, t2), null, a);
  select deleted_at into d from public.tasks where id = t2;
  perform pg_temp.assert('tombstone time is server time', d > now() - interval '1 minute');
  perform pg_temp.expect('tombstone cannot be reverted', format($f$update public.tasks set deleted_at = null where id=%L$f$, t2), '23514', a);

  -- tree integrity
  perform pg_temp.expect('self parent rejected', format($f$update public.tasks set parent_id=id where id=%L$f$, t1), '23514', a);
  perform pg_temp.expect('cycle rejected', format($f$update public.tasks set parent_id=%L where id=%L$f$, t2, t1), '23514', a);
  perform pg_temp.expect('A inserts task in project 2', format($f$insert into public.tasks(id,project_id,owner_id,title) values (%L,%L,%L,'T3')$f$, t3, pa2, a), null, a);
  perform pg_temp.expect('cross-project parent rejected', format($f$update public.tasks set parent_id=%L where id=%L$f$, t3, t1), '23503', a);

  -- value contract
  perform pg_temp.expect('status review ok', format($f$update public.tasks set status='review' where id=%L$f$, t1), null, a);
  perform pg_temp.expect('status archived ok', format($f$update public.tasks set status='archived' where id=%L$f$, t1), null, a);
  perform pg_temp.expect('status ready_for_review rejected', format($f$update public.tasks set status='ready_for_review' where id=%L$f$, t1), '23514', a);
  perform pg_temp.expect('priority none ok', format($f$update public.tasks set priority='none' where id=%L$f$, t1), null, a);
  perform pg_temp.expect('title 201 chars rejected', format($f$update public.tasks set title=repeat('x',201) where id=%L$f$, t1), '23514', a);
  perform pg_temp.assert('notes default empty', (select notes from public.tasks where id=t3) = '');

  -- sync foundation is inert and isolated
  insert into public.devices(id,user_id) values ('dddddddd-0000-0000-0000-00000000000a', a), ('dddddddd-0000-0000-0000-00000000000b', b);
  insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,request_hash,status,server_seq)
    values (a,'cccccccc-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-00000000000a','task',t1,'update','h','applied',1);
  perform pg_temp.assert('A sees own operation', pg_temp.count_as('select count(*) from public.sync_operations', a) = 1);
  perform pg_temp.assert('B sees no operation', pg_temp.count_as('select count(*) from public.sync_operations', b) = 0);
  perform pg_temp.assert('B sees only own device', pg_temp.count_as('select count(*) from public.devices', b) = 1);
  perform pg_temp.expect('client cannot write sync_operations', format($f$insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,request_hash,status,server_seq) values (%L,gen_random_uuid(),'dddddddd-0000-0000-0000-00000000000b','task',%L,'update','h','applied',1)$f$, b, t1), '42501', b);
  perform pg_temp.expect('client cannot write sync_conflicts', 'insert into public.sync_conflicts(user_id,operation_id,entity_type,entity_id,fields,base_version,server_version,server_value,client_value) values (gen_random_uuid(),gen_random_uuid(),''task'',gen_random_uuid(),array[''title''],1,2,''{}'',''{}'')', '42501', a);
  perform pg_temp.expect('client cannot write devices', format($f$insert into public.devices(id,user_id) values (gen_random_uuid(),%L)$f$, a), '42501', a);
  begin
    insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,request_hash,status,server_seq)
      values (b,'cccccccc-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-00000000000a','task',t1,'update','h','applied',1);
    raise exception 'FAIL [device of another user accepted]';
  exception when foreign_key_violation then insert into _r values ('operation cannot use another user''s device', true); end;
  insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,request_hash,status,server_seq)
    values (b,'cccccccc-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-00000000000b','task',t1,'update','h','applied',1);
  insert into _r values ('same operation_id allowed per different user (no cross-user probing)', true);
  begin
    insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,request_hash,status,server_seq)
      values (a,'cccccccc-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-00000000000a','task',t1,'update','h','applied',1);
    raise exception 'FAIL [duplicate operation accepted]';
  exception when unique_violation then insert into _r values ('duplicate operation_id rejected (idempotency)', true); end;

  -- rls_auto_enable
  perform pg_temp.expect('anon cannot execute rls_auto_enable', 'select public.rls_auto_enable()', '42501', null, 'anon');
  perform pg_temp.expect('authenticated cannot execute rls_auto_enable', 'select public.rls_auto_enable()', '42501', a);
  perform pg_temp.expect('authenticated cannot call guard_row', 'select nexora_private.guard_row()', '42501', a);
  create table public._ddl_probe(id int);
  perform pg_temp.assert('event trigger still enables RLS on new tables', (select relrowsecurity from pg_class where oid='public._ddl_probe'::regclass));
  perform pg_temp.assert('no anon grant on new table (default privileges)', not has_table_privilege('anon','public._ddl_probe','select'));
end $$;

select count(*) as passed from _r;
rollback;
