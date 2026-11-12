-- S1 sync protocol schema suite. Rollback-only. Requires migrations through ..._nexora_sync_protocol_schema.
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
create function pg_temp.holds_user_lock(p_user uuid) returns boolean language sql as $$
  select exists (select 1 from pg_locks where locktype='advisory' and pid=pg_backend_pid() and granted
    and ((classid::bigint << 32) | objid::bigint) = hashtextextended(p_user::text, 0)) $$;

do $$
declare
  a uuid := '00000000-0000-0000-0000-00000000000a';
  b uuid := '00000000-0000-0000-0000-00000000000b';
  c uuid := '00000000-0000-0000-0000-00000000000c';
  pa uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  t1 uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  fv jsonb; v bigint; i int; op uuid := 'cccccccc-0000-0000-0000-0000000000c1';
  dev uuid := 'dddddddd-0000-0000-0000-0000000000c1';
begin
  insert into auth.users(id) values (a), (b), (c);
  perform pg_temp.expect('A inserts project', format($f$insert into public.projects(id,owner_id,name) values (%L,%L,'P')$f$, pa, a), null, a);
  perform pg_temp.expect('A inserts task', format($f$insert into public.tasks(id,project_id,owner_id,title) values (%L,%L,%L,'T1')$f$, t1, pa, a), null, a);

  -- field_versions: per-field change tracking, server-owned
  select field_versions into fv from public.tasks where id = t1;
  perform pg_temp.assert('insert starts with empty field_versions', fv = '{}'::jsonb);
  perform pg_temp.expect('title edit', format($f$update public.tasks set title='T1b' where id=%L$f$, t1), null, a);
  select field_versions, version into fv, v from public.tasks where id = t1;
  perform pg_temp.assert('only title tracked at version 2', fv = '{"title":2}'::jsonb and v = 2);
  perform pg_temp.expect('status edit', format($f$update public.tasks set status='in_progress' where id=%L$f$, t1), null, a);
  select field_versions into fv from public.tasks where id = t1;
  perform pg_temp.assert('status v3, title still v2', fv = '{"title":2,"status":3}'::jsonb);
  perform pg_temp.expect('no-op edit', format($f$update public.tasks set title='T1b' where id=%L$f$, t1), null, a);
  select field_versions, version into fv, v from public.tasks where id = t1;
  perform pg_temp.assert('unchanged field keeps its version', fv = '{"title":2,"status":3}'::jsonb and v = 4);
  perform pg_temp.expect('forged field_versions', format($f$update public.tasks set field_versions='{"title":99}', notes='n' where id=%L$f$, t1), null, a);
  select field_versions into fv from public.tasks where id = t1;
  perform pg_temp.assert('forged field_versions ignored, notes tracked', fv = '{"title":2,"status":3,"notes":5}'::jsonb);
  perform pg_temp.expect('soft delete', format($f$update public.tasks set deleted_at=now() where id=%L$f$, t1), null, a);
  select field_versions into fv from public.tasks where id = t1;
  perform pg_temp.assert('deleted_at tracked', (fv->>'deleted_at')::int = 6);
  perform pg_temp.expect('project rename', format($f$update public.projects set name='P1', sort_order=3 where id=%L$f$, pa), null, a);
  select field_versions into fv from public.projects where id = pa;
  perform pg_temp.assert('project fields tracked', fv = '{"name":2,"sort_order":2}'::jsonb);

  -- replica mode cannot bypass guards
  set local session_replication_role = replica;
  update public.projects set name = 'P2' where id = pa;
  set local session_replication_role = origin;
  select version into v from public.projects where id = pa;
  perform pg_temp.assert('guard trigger fires even in replica mode', v = 3);

  -- lock discipline on every write path that assigns change_seq
  perform pg_temp.expect('authenticated write', format($f$update public.projects set name='P3' where id=%L$f$, pa), null, a);
  perform pg_temp.assert('direct authenticated write took the user lock', pg_temp.holds_user_lock(a));
  perform pg_temp.assert('lock not held for other user', not pg_temp.holds_user_lock(b));
  perform pg_temp.expect('service_role write', format($f$update public.projects set name='P4' where id=%L$f$, pa), null, null, 'service_role');
  perform pg_temp.assert('service_role path uses the same lock', pg_temp.holds_user_lock(a));
  perform pg_temp.expect('forged owner insert rejected before locking', format($f$insert into public.projects(owner_id,name) values (%L,'x')$f$, a), '42501', b);
  perform pg_temp.assert('coverage: every change_seq table has an enabled-always guard trigger',
    not exists (select 1 from information_schema.columns c
       where c.table_schema='public' and c.column_name='change_seq'
         and not exists (select 1 from pg_trigger g where g.tgrelid=(quote_ident(c.table_schema)||'.'||quote_ident(c.table_name))::regclass
              and g.tgfoid='nexora_private.guard_row()'::regprocedure and g.tgenabled='A')));

  -- conflicts: kind and audit columns
  insert into public.devices(id,user_id) values (dev, c);
  insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,base_version,patch,request_hash,status,server_seq)
    values (c, op, dev, 'task', t1, 'update', 1, '{"title":"mine"}', 'h', 'conflict', 1);
  perform pg_temp.expect('conflict kind required', format($f$insert into public.sync_conflicts(user_id,operation_id,entity_type,entity_id,fields,base_version,server_version,server_value,client_value) values (%L,%L,'task',%L,array['title'],1,2,'{}','{}')$f$, c, op, t1), '23502', null, 'postgres');
  perform pg_temp.expect('unknown kind rejected', format($f$insert into public.sync_conflicts(user_id,operation_id,kind,entity_type,entity_id,fields,base_version,server_version,server_value,client_value) values (%L,%L,'bogus','task',%L,array['title'],1,2,'{}','{}')$f$, c, op, t1), '23514', null, 'postgres');
  insert into public.sync_conflicts(id,user_id,operation_id,kind,entity_type,entity_id,fields,base_version,server_version,server_value,client_value)
    values ('eeeeeeee-0000-0000-0000-0000000000c1', c, op, 'field', 'task', t1, array['title'], 1, 2, '{"title":"server"}', '{"title":"mine"}');
  perform pg_temp.expect('resolved needs a resolution source', $f$update public.sync_conflicts set status='resolved_server', resolved_at=now() where id='eeeeeeee-0000-0000-0000-0000000000c1'$f$, '23514', null, 'postgres');
  perform pg_temp.expect('policy only with auto_policy source', $f$update public.sync_conflicts set status='resolved_server', resolved_at=now(), resolution_source='user', resolution_policy='sort_order_server_wins' where id='eeeeeeee-0000-0000-0000-0000000000c1'$f$, '23514', null, 'postgres');
  perform pg_temp.expect('preserved values immutable', $f$update public.sync_conflicts set server_value='{}' where id='eeeeeeee-0000-0000-0000-0000000000c1'$f$, '23514', null, 'postgres');
  perform pg_temp.expect('conflict cannot be deleted directly', $f$delete from public.sync_conflicts where id='eeeeeeee-0000-0000-0000-0000000000c1'$f$, '23514', null, 'postgres');
  perform pg_temp.expect('operation log is append-only (update)', format($f$update public.sync_operations set patch='{}' where user_id=%L and operation_id=%L$f$, c, op), '23514', null, 'postgres');
  perform pg_temp.expect('operation log is append-only (delete)', format($f$delete from public.sync_operations where user_id=%L and operation_id=%L$f$, c, op), '23514', null, 'postgres');
  perform pg_temp.expect('auto policy resolution allowed', $f$update public.sync_conflicts set status='resolved_server', resolved_at=now(), resolution_source='auto_policy', resolution_policy='sort_order_server_wins' where id='eeeeeeee-0000-0000-0000-0000000000c1'$f$, null, null, 'postgres');
  perform pg_temp.expect('resolved conflict is final', $f$update public.sync_conflicts set status='resolved_client' where id='eeeeeeee-0000-0000-0000-0000000000c1'$f$, '23514', null, 'postgres');
  perform pg_temp.assert('both values still present', (select server_value->>'title' = 'server' and client_value->>'title' = 'mine' from public.sync_conflicts where id='eeeeeeee-0000-0000-0000-0000000000c1'));

  -- account deletion still cascades through the append-only tables
  perform pg_temp.expect('deleting a user cascades devices, operations and conflicts', format($f$delete from auth.users where id=%L$f$, c), null, null, 'postgres');
  perform pg_temp.assert('cascade left nothing behind', not exists (select 1 from public.sync_operations where user_id=c) and not exists (select 1 from public.devices where user_id=c));

  -- device cap
  for i in 1..10 loop
    insert into public.devices(id,user_id) values (('dddddddd-0000-0000-0000-0000000001' || lpad(i::text,2,'0'))::uuid, b);
  end loop;
  perform pg_temp.expect('11th active device rejected', format($f$insert into public.devices(id,user_id) values (gen_random_uuid(), %L)$f$, b), '54000', null, 'postgres');
  update public.devices set revoked_at = now() where id = 'dddddddd-0000-0000-0000-000000000101';
  perform pg_temp.expect('slot frees after revoke', format($f$insert into public.devices(id,user_id) values (gen_random_uuid(), %L)$f$, b), null, null, 'postgres');
  perform pg_temp.expect('un-revoking beyond the cap rejected', $f$update public.devices set revoked_at = null where id = 'dddddddd-0000-0000-0000-000000000101'$f$, '54000', null, 'postgres');
  perform pg_temp.expect('device id and user immutable', format($f$update public.devices set user_id=%L where id='dddddddd-0000-0000-0000-000000000102'$f$, a), '23514', null, 'postgres');

  -- grants and exposure unchanged by S1
  perform pg_temp.expect('anon still cannot read devices', 'select * from public.devices', '42501', null, 'anon');
  perform pg_temp.expect('client cannot call lock_user', format($f$select nexora_private.lock_user(%L)$f$, a), '42501', a);
  perform pg_temp.expect('client cannot use nexora_private schema', 'select nexora_private.user_lock_key(gen_random_uuid())', '42501', a);
end $$;

select count(*) as passed from _r;
rollback;
