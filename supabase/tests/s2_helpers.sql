-- Shared helpers for the S2 suites. Included with \ir after "begin;". Everything lives in pg_temp.
create temp table _r(name text, ok boolean);
grant all on _r to public;

create function pg_temp.assert(label text, cond boolean) returns void language plpgsql as $$
begin if cond is not true then raise exception 'FAIL [%]', label; end if; insert into _r values (label, true); end $$;

-- Runs one statement exactly like PostgREST would: JWT claims as request.jwt.claims JSON, then SET ROLE.
-- Returns the statement's jsonb result, or {"error": {"sqlstate", "message"}} when it raises.
create function pg_temp.rpc(uid uuid, stmt text, anon boolean default false, role_name text default 'authenticated',
                            extra jsonb default '{}'::jsonb) returns jsonb language plpgsql as $$
declare r jsonb; claims jsonb;
begin
  claims := jsonb_build_object('role', role_name, 'aud', 'authenticated', 'is_anonymous', anon,
                               'app_metadata', jsonb_build_object('provider', 'email'), 'user_metadata', '{}'::jsonb);
  if uid is not null then claims := claims || jsonb_build_object('sub', uid); end if;
  claims := claims || extra;
  perform set_config('request.jwt.claims', claims::text, true);
  perform set_config('request.jwt.claim.sub', '', true);
  execute format('set local role %I', role_name);
  begin
    execute stmt into r;
  exception when others then
    r := jsonb_build_object('error', jsonb_build_object('sqlstate', sqlstate, 'message', sqlerrm));
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return r;
end $$;

create function pg_temp.u(prefix text, n int) returns uuid language sql immutable as
$$ select (prefix || '-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid $$;

create function pg_temp.mkuser(id uuid) returns void language sql as $$ insert into auth.users(id) values (id) $$;

create function pg_temp.reg(uid uuid, dev uuid, label text default null, anon boolean default false) returns jsonb language sql as
$$ select pg_temp.rpc(uid, format('select public.nexora_register_device(%L, %L)', dev, label), anon) $$;

create function pg_temp.push(uid uuid, dev uuid, ops jsonb, anon boolean default false) returns jsonb language sql as
$$ select pg_temp.rpc(uid, format('select public.nexora_sync_push(%L, %L::jsonb)', dev, ops::text), anon) $$;

create function pg_temp.op(opid uuid, etype text, eid uuid, otype text, base bigint, patch jsonb default null) returns jsonb language sql as
$$ select jsonb_build_object('operation_id', opid, 'entity_type', etype, 'entity_id', eid, 'op_type', otype)
     || case when base is not null then jsonb_build_object('base_version', base) else '{}'::jsonb end
     || case when patch is not null then jsonb_build_object('patch', patch) else '{}'::jsonb end $$;

-- first result of a one-operation push
create function pg_temp.one(uid uuid, dev uuid, o jsonb) returns jsonb language sql as
$$ select (pg_temp.push(uid, dev, jsonb_build_array(o))) -> 'results' -> 0 $$;

create function pg_temp.err(r jsonb) returns text language sql immutable as $$ select r -> 'error' ->> 'sqlstate' $$;
create function pg_temp.msg(r jsonb) returns text language sql immutable as $$ select r -> 'error' ->> 'message' $$;

create function pg_temp.holds_user_lock(p_user uuid) returns boolean language sql as $$
  select exists (select 1 from pg_locks where locktype='advisory' and pid=pg_backend_pid() and granted
    and ((classid::bigint << 32) | objid::bigint) = hashtextextended(p_user::text, 0)) $$;

create temp sequence _opn;
create function pg_temp.nid() returns uuid language sql as $$ select pg_temp.u('c0000000', nextval('_opn')::int) $$;
-- one operation, fresh operation_id
create function pg_temp.c(uid uuid, dev uuid, etype text, eid uuid, otype text, base bigint, patch jsonb default null) returns jsonb language sql as
$$ select pg_temp.one(uid, dev, pg_temp.op(pg_temp.nid(), etype, eid, otype, base, patch)) $$;
