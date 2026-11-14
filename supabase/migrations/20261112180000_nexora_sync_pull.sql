-- Phase 3 / S4: cursor-based incremental pull. Additive: one column on sync_conflicts (so conflicts travel in the same
-- ordered change stream as entities), one trigger, one column on devices, indexes, and one function pair.
-- Cursor safety (decision D-L): every writer of one user takes the per-user advisory lock before it allocates
-- change_seq and holds it until commit, so the committed change_seq values of one user are commit-ordered and a pull
-- can never skip a row that commits later. Cursor values are NOT contiguous (the sequence is shared by all users and by
-- operation records) and the client must not assume they are.
-- Contract: docs/architecture/s3-s4-wire-contract.md. Rollback: supabase/rollback/20261112180000_rollback_s4_sync_pull.sql.

-- 1. Conflicts join the change stream: change_seq is assigned on insert and on resolution (an UPDATE), under the user lock.
alter table public.sync_conflicts add column change_seq bigint not null default 0;
create function nexora_private.guard_conflict_seq() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.change_seq := nextval('nexora_private.change_seq');
  return new;
end $$;
revoke execute on function nexora_private.guard_conflict_seq() from public, anon, authenticated;
create trigger sync_conflicts_seq before insert or update on public.sync_conflicts
  for each row execute function nexora_private.guard_conflict_seq();
alter table public.sync_conflicts enable always trigger sync_conflicts_seq;

alter table public.devices add column last_pull_at timestamptz;

-- 2. Index for the third ordered scan (projects and tasks already have (owner_id, change_seq) indexes from Phase 2B).
create index sync_conflicts_user_seq_idx on public.sync_conflicts (user_id, change_seq);

-- 3. Pull. Returns {changes: [{entity_type, row}], conflicts: [row], next_cursor, has_more}. A page holds at most
--    p_limit items (default 200, at most 500) and at most 1,048,576 bytes of row text, except that the first item
--    is always returned (a single row can exceed the byte bound). Entities and conflicts are one stream ordered by
--    change_seq; next_cursor is the change_seq of the last item of the page (or the request cursor when empty).
create function nexora_private.pull(p_device_id uuid, p_cursor bigint, p_limit int default 200) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_user uuid; v_limit int; v_high bigint;
  v_changes jsonb; v_conflicts jsonb; v_next bigint; v_more boolean;
begin
  v_user := nexora_private.sync_user();
  if p_device_id is null or (p_limit is not null and p_limit < 1) then
    raise exception 'invalid_request' using errcode = 'NX005';
  end if;
  if p_cursor is null or p_cursor < 0 then raise exception 'invalid_cursor' using errcode = 'NX006'; end if;
  v_limit := least(coalesce(p_limit, 200), 500);
  perform 1 from public.devices where id = p_device_id and user_id = v_user and revoked_at is null;
  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;
  -- A cursor ahead of everything the server ever issued cannot come from this server's stream.
  select case when is_called then last_value else 0 end into v_high from nexora_private.change_seq;
  if p_cursor > v_high then raise exception 'invalid_cursor' using errcode = 'NX006'; end if;
  update public.devices set last_pull_at = now(), last_seen_at = now() where id = p_device_id;

  with items as (
    (select p.change_seq as seq, 'project'::text as kind, to_jsonb(p) as j from public.projects p
      where p.owner_id = v_user and p.change_seq > p_cursor order by p.change_seq limit v_limit + 1)
    union all
    (select t.change_seq, 'task'::text, to_jsonb(t) from public.tasks t
      where t.owner_id = v_user and t.change_seq > p_cursor order by t.change_seq limit v_limit + 1)
    union all
    (select c.change_seq, 'conflict'::text, to_jsonb(c) from public.sync_conflicts c
      where c.user_id = v_user and c.change_seq > p_cursor order by c.change_seq limit v_limit + 1)
  ), ordered as (
    select x.seq, x.kind, x.j, octet_length(x.j::text) as sz, row_number() over (order by x.seq) as rn
      from (select * from items order by seq limit v_limit + 1) x
  ), sized as (
    select o.*, coalesce(sum(o.sz) over (order by o.seq rows between unbounded preceding and 1 preceding), 0) as prior
      from ordered o
  ), paged as (
    select s.*, (s.rn <= v_limit and (s.rn = 1 or s.prior + s.sz <= 1048576)) as in_page from sized s
  )
  select coalesce(jsonb_agg(jsonb_build_object('entity_type', kind, 'row', j) order by seq) filter (where in_page and kind <> 'conflict'), '[]'::jsonb),
         coalesce(jsonb_agg(j order by seq) filter (where in_page and kind = 'conflict'), '[]'::jsonb),
         max(seq) filter (where in_page),
         coalesce(bool_or(not in_page), false)
    into v_changes, v_conflicts, v_next, v_more
    from paged;
  return jsonb_build_object('changes', v_changes, 'conflicts', v_conflicts,
                            'next_cursor', coalesce(v_next, p_cursor), 'has_more', v_more);
end $$;

create function public.nexora_sync_pull(p_device_id uuid, p_cursor bigint, p_limit int default 200) returns jsonb
language sql security invoker set search_path = '' as
$$ select nexora_private.pull(p_device_id, p_cursor, p_limit) $$;

revoke all on function nexora_private.pull(uuid, bigint, int), public.nexora_sync_pull(uuid, bigint, int)
  from public, anon, authenticated, service_role;
grant execute on function nexora_private.pull(uuid, bigint, int), public.nexora_sync_pull(uuid, bigint, int) to authenticated;
