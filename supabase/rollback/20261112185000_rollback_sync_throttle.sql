-- Rollback of S10a (throttle). Restores the previous private entry points exactly and drops the throttle objects.
-- Counters hold no user data, so nothing needs to be preserved or checked.
begin;
create or replace function nexora_private.register_device(p_device_id uuid, p_label text) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_user uuid; v_dev public.devices; v_created boolean := false; v_active int;
begin
  v_user := nexora_private.sync_user();
  if p_device_id is null or (p_label is not null and length(p_label) > 100) then
    raise exception 'invalid_request' using errcode = 'NX005';
  end if;
  perform nexora_private.lock_user(v_user);
  select * into v_dev from public.devices where id = p_device_id;
  if found then
    if v_dev.user_id <> v_user or v_dev.revoked_at is not null then
      raise exception 'device_invalid' using errcode = 'NX001';
    end if;
    update public.devices set last_seen_at = now() where id = p_device_id;
  else
    begin
      insert into public.devices(id, user_id, label, last_seen_at) values (p_device_id, v_user, p_label, now());
      v_created := true;
    exception when sqlstate '54000' then
      raise exception 'device_limit' using errcode = 'NX002';
    end;
  end if;
  select count(*) into v_active from public.devices where user_id = v_user and revoked_at is null;
  return jsonb_build_object('device_id', p_device_id, 'created', v_created, 'active_devices', v_active);
end $$;

create or replace function nexora_private.push(p_device_id uuid, p_ops jsonb) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_user uuid; n int; i int; v_results jsonb := '[]'::jsonb;
begin
  v_user := nexora_private.sync_user();
  if p_device_id is null or p_ops is null or jsonb_typeof(p_ops) <> 'array' or jsonb_array_length(p_ops) = 0 then
    raise exception 'invalid_request' using errcode = 'NX005';
  end if;
  n := jsonb_array_length(p_ops);
  if n > 100 then raise exception 'batch_too_large' using errcode = 'NX003'; end if;
  if octet_length(p_ops::text) > 1048576 then raise exception 'payload_too_large' using errcode = 'NX004'; end if;
  perform nexora_private.lock_user(v_user);
  perform 1 from public.devices where id = p_device_id and user_id = v_user and revoked_at is null;
  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;
  update public.devices set last_push_at = now(), last_seen_at = now() where id = p_device_id;
  for i in 0 .. n - 1 loop
    v_results := v_results || jsonb_build_array(nexora_private.apply_operation(v_user, p_device_id, p_ops -> i));
  end loop;
  return jsonb_build_object('results', v_results);
end $$;

create or replace function nexora_private.resolve_conflict(p_device_id uuid, p_operation_id uuid, p_conflict_id uuid,
                                                p_resolution text, p_values jsonb default null) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare
  v_user uuid; v_c public.sync_conflicts; v_ex public.sync_operations; v_hash text;
  v_state text; v_msg text; v_err text; v_result jsonb;
begin
  v_user := nexora_private.sync_user();
  if p_device_id is null or p_operation_id is null or p_conflict_id is null or p_resolution is null
     or p_resolution not in ('resolved_server', 'resolved_client', 'resolved_merged', 'recreate_copy')
     or (p_values is not null and jsonb_typeof(p_values) <> 'object') then
    raise exception 'invalid_request' using errcode = 'NX005';
  end if;
  perform nexora_private.lock_user(v_user);
  perform 1 from public.devices where id = p_device_id and user_id = v_user and revoked_at is null;
  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;
  update public.devices set last_seen_at = now() where id = p_device_id;

  v_hash := encode(sha256(convert_to(concat_ws('|', 'resolve', p_conflict_id::text, p_resolution,
                                               coalesce(p_values::text, '')), 'utf8')), 'hex');
  select * into v_ex from public.sync_operations where user_id = v_user and operation_id = p_operation_id;
  if found then
    if v_ex.op_type = 'resolve' and v_ex.request_hash = v_hash then return v_ex.result || '{"replayed": true}'::jsonb; end if;
    return jsonb_build_object('operation_id', p_operation_id, 'status', 'rejected', 'error_code', 'operation_id_reuse', 'replayed', false);
  end if;
  select * into v_c from public.sync_conflicts where id = p_conflict_id and user_id = v_user;
  if not found then   -- unknown and foreign conflicts are indistinguishable; nothing to record against
    return jsonb_build_object('operation_id', p_operation_id, 'status', 'rejected', 'error_code', 'not_found', 'replayed', false);
  end if;
  begin
    return nexora_private.resolve_core(v_user, p_device_id, p_operation_id, v_c, p_resolution, p_values, v_hash);
  exception when others then
    v_state := sqlstate; v_msg := sqlerrm;
    if v_state = 'NXO01' then v_err := v_msg;
    elsif v_msg = 'task parent cycle' then v_err := 'parent_invalid';
    elsif left(v_state, 2) in ('22', '23') then v_err := 'invalid_patch';
    else raise;   -- transient or unexpected: abort the call, record nothing
    end if;
  end;
  v_result := jsonb_build_object('operation_id', p_operation_id, 'status', 'rejected', 'error_code', v_err,
                                 'conflict_id', p_conflict_id, 'replayed', false);
  insert into public.sync_operations(user_id, operation_id, device_id, entity_type, entity_id, op_type, base_version, patch,
                                     request_hash, status, result, applied_version, server_seq)
  values (v_user, p_operation_id, p_device_id, v_c.entity_type, v_c.entity_id, 'resolve', null,
          jsonb_build_object('conflict_id', p_conflict_id, 'resolution', p_resolution, 'values', coalesce(p_values, 'null'::jsonb)),
          v_hash, 'rejected', v_result, null, nextval('nexora_private.change_seq'));
  return v_result;
end $$;

create or replace function nexora_private.revoke_device(p_device_id uuid, p_target_device_id uuid) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_user uuid; v_dev public.devices; v_newly boolean := false; v_active int;
begin
  v_user := nexora_private.sync_user();
  if p_device_id is null or p_target_device_id is null then raise exception 'invalid_request' using errcode = 'NX005'; end if;
  perform nexora_private.lock_user(v_user);
  perform 1 from public.devices where id = p_device_id and user_id = v_user and revoked_at is null;
  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;
  select * into v_dev from public.devices where id = p_target_device_id and user_id = v_user;
  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;
  if v_dev.revoked_at is null then
    update public.devices set revoked_at = now() where id = p_target_device_id;
    v_newly := true;
  end if;
  select count(*) into v_active from public.devices where user_id = v_user and revoked_at is null;
  return jsonb_build_object('device_id', p_target_device_id, 'revoked', v_newly, 'active_devices', v_active);
end $$;

create or replace function nexora_private.pull(p_device_id uuid, p_cursor bigint, p_limit int default 200) returns jsonb
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

drop function nexora_private.throttle(uuid, text, int);
drop table nexora_private.rate_bucket;
drop table nexora_private.rate_policy;
commit;
