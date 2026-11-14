-- Helpers for the S3/S4 suites (after s2_helpers.sql). Everything lives in pg_temp.
create function pg_temp.pull(uid uuid, dev uuid, cur bigint, lim int default 200, anon boolean default false) returns jsonb language sql as
$$ select pg_temp.rpc(uid, format('select public.nexora_sync_pull(%L, %s, %s)', dev, coalesce(cur::text, 'null'), coalesce(lim::text, 'null')), anon) $$;

create function pg_temp.resolve(uid uuid, dev uuid, opid uuid, cid uuid, strat text, vals jsonb default null, anon boolean default false) returns jsonb language sql as
$$ select pg_temp.rpc(uid, format('select public.nexora_resolve_conflict(%L, %L, %L, %L, %L::jsonb)', dev, opid, cid, strat, vals::text), anon) $$;

create function pg_temp.revoke(uid uuid, dev uuid, target uuid, anon boolean default false) returns jsonb language sql as
$$ select pg_temp.rpc(uid, format('select public.nexora_revoke_device(%L, %L)', dev, target), anon) $$;

-- one resolution with a fresh operation id
create function pg_temp.res(uid uuid, dev uuid, cid uuid, strat text, vals jsonb default null) returns jsonb language sql as
$$ select pg_temp.resolve(uid, dev, pg_temp.nid(), cid, strat, vals) $$;

-- the open conflict id of an entity
create function pg_temp.open_conflict(eid uuid) returns uuid language sql as
$$ select id from public.sync_conflicts where entity_id = eid and status = 'open' order by change_seq desc limit 1 $$;

create function pg_temp.maxseq(uid uuid) returns bigint language sql as
$$ select greatest(coalesce((select max(change_seq) from public.projects where owner_id = uid), 0),
                   coalesce((select max(change_seq) from public.tasks where owner_id = uid), 0),
                   coalesce((select max(change_seq) from public.sync_conflicts where user_id = uid), 0)) $$;

-- All pages from a cursor, as one {changes, conflicts, next_cursor, pages} object (walks has_more).
create function pg_temp.pull_all(uid uuid, dev uuid, cur bigint, lim int default 200) returns jsonb language plpgsql as $$
declare r jsonb; ch jsonb := '[]'::jsonb; cf jsonb := '[]'::jsonb; c bigint := cur; pages int := 0;
begin
  loop
    r := pg_temp.pull(uid, dev, c, lim);
    if r ? 'error' then return r; end if;
    ch := ch || (r -> 'changes'); cf := cf || (r -> 'conflicts'); c := (r ->> 'next_cursor')::bigint; pages := pages + 1;
    exit when r ->> 'has_more' = 'false' or pages > 200;
  end loop;
  return jsonb_build_object('changes', ch, 'conflicts', cf, 'next_cursor', c, 'pages', pages);
end $$;
