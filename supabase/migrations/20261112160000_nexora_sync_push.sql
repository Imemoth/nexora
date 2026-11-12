-- Phase 3 / S2: device registration and idempotent push (server side). FUNCTIONS ONLY: no table, column,
-- policy or table-grant change. Synchronization stays disabled until the S9 activation gate.
-- Contract: docs/architecture/s2-wire-contract.md. Architecture: D-R (public SECURITY INVOKER wrappers
-- over private SECURITY DEFINER implementations). Every function sets search_path = ''.
-- Order inside a push: per-user lock -> look up operation_id -> validate -> apply in a sub-transaction ->
-- insert the final, immutable result row ONCE (sync_operations is append-only since S1).

-- 1. Identity: the user comes only from the verified JWT claims (auth.uid()); anonymous users are refused.
create function nexora_private.sync_user() returns uuid
language plpgsql stable set search_path = '' as $$
declare v_uid uuid; v_claims jsonb; v_anon boolean;
begin
  begin v_uid := auth.uid(); exception when others then v_uid := null; end;
  if v_uid is null then raise exception 'unauthenticated' using errcode = '28000'; end if;
  begin v_claims := auth.jwt(); exception when others then v_claims := null; end;
  -- The user must still exist (deleting a user does not invalidate an existing access token), and the
  -- authoritative auth.users flag is checked in addition to the token's is_anonymous claim.
  select u.is_anonymous into v_anon from auth.users u where u.id = v_uid;
  if not found then raise exception 'unauthenticated' using errcode = '28000'; end if;
  if v_anon or lower(coalesce(v_claims ->> 'is_anonymous', 'false')) = 'true' then
    raise exception 'anonymous_not_allowed' using errcode = '42501';
  end if;
  return v_uid;
end $$;

-- 2. Patch grammar: key -> [json type, nullable]. Server-owned and immutable columns are absent on purpose.
create function nexora_private.patch_spec(p_etype text, p_create boolean) returns jsonb
language sql immutable set search_path = '' as $$
  select case p_etype
    when 'project' then '{"name":["string",false],"description":["string",true],"color":["string",true],"is_archived":["boolean",false],"sort_order":["number",false]}'::jsonb
    else '{"parent_id":["string",true],"title":["string",false],"notes":["string",false],"status":["string",false],"priority":["string",false],"due_date":["string",true],"completed_at":["string",true],"sort_order":["number",false]}'::jsonb
         || case when p_create then '{"project_id":["string",false]}'::jsonb else '{}'::jsonb end
  end $$;

create function nexora_private.check_parent(p_user uuid, p_project uuid, p_parent uuid, p_self uuid) returns void
language plpgsql set search_path = '' as $$
begin
  if p_parent = p_self then raise exception 'parent_invalid' using errcode = 'NXO01'; end if;
  perform 1 from public.tasks t
   where t.id = p_parent and t.owner_id = p_user and t.project_id = p_project and t.deleted_at is null;
  if not found then raise exception 'parent_invalid' using errcode = 'NXO01'; end if;
end $$;

-- 3. One operation: validates, authorizes, applies, and records the final result. Raises NXO01 (message =
--    error code) for terminal rejections; the caller records those. Called only by apply_operation.
create function nexora_private.apply_core(p_user uuid, p_device uuid, p_opid uuid, p_etype text, p_eid uuid,
                                          p_otype text, p_op jsonb, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tbl text := case p_etype when 'project' then 'projects' else 'tasks' end;
  v_spec jsonb; v_patch jsonb := '{}'::jsonb; v_base bigint; v_cca timestamptz;
  k text; val jsonb; v_cur jsonb; v_norm jsonb; v_ver bigint;
  v_status text; v_row jsonb; v_applied_version bigint;
  v_cid uuid; v_kind text; v_fields text[]; v_sv jsonb; v_cv jsonb; v_auto boolean := false;
  v_conf text[] := '{}'; v_app text[] := '{}'; v_apply jsonb; v_cols text; v_result jsonb; v_proj uuid;
  v_pj jsonb;
begin
  -- operation shape
  if exists (select 1 from jsonb_object_keys(p_op) o(key)
              where o.key not in ('operation_id','entity_type','entity_id','op_type','base_version','patch','client_created_at')) then
    raise exception 'invalid_op' using errcode = 'NXO01';
  end if;
  if p_op ? 'client_created_at' and jsonb_typeof(p_op -> 'client_created_at') <> 'null' then
    begin v_cca := (p_op ->> 'client_created_at')::timestamptz;
    exception when others then raise exception 'invalid_op' using errcode = 'NXO01'; end;
  end if;
  if p_otype = 'create' then
    if p_op ? 'base_version' and jsonb_typeof(p_op -> 'base_version') <> 'null'
       and not (jsonb_typeof(p_op -> 'base_version') = 'number' and (p_op ->> 'base_version') = '0') then
      raise exception 'invalid_op' using errcode = 'NXO01';
    end if;
  else
    if jsonb_typeof(p_op -> 'base_version') is distinct from 'number'
       or (p_op ->> 'base_version') !~ '^[0-9]{1,18}$' or (p_op ->> 'base_version')::bigint < 1 then
      raise exception 'invalid_op' using errcode = 'NXO01';
    end if;
    v_base := (p_op ->> 'base_version')::bigint;
  end if;
  if p_otype = 'delete' then
    if p_op ? 'patch' and not (p_op -> 'patch' = '{}'::jsonb or p_op -> 'patch' = 'null'::jsonb) then
      raise exception 'invalid_op' using errcode = 'NXO01';
    end if;
  else
    if jsonb_typeof(p_op -> 'patch') is distinct from 'object' then raise exception 'invalid_op' using errcode = 'NXO01'; end if;
    v_patch := p_op -> 'patch';
    if octet_length(v_patch::text) > 262144 then raise exception 'payload_too_large' using errcode = 'NXO01'; end if;
    v_spec := nexora_private.patch_spec(p_etype, p_otype = 'create');
    for k, val in select e.key, e.value from jsonb_each(v_patch) e loop
      if not (v_spec ? k) then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;
      if jsonb_typeof(val) = 'null' then
        if not (v_spec -> k ->> 1)::boolean then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;
      elsif jsonb_typeof(val) <> (v_spec -> k ->> 0) then
        raise exception 'invalid_patch' using errcode = 'NXO01';
      end if;
    end loop;
  end if;

  -- an entity with an open conflict of this user accepts no further operations until it is resolved
  if exists (select 1 from public.sync_conflicts c where c.user_id = p_user and c.entity_type = p_etype
              and c.entity_id = p_eid and c.status = 'open') then
    raise exception 'blocked_by_conflict' using errcode = 'NXO01';
  end if;

  if p_otype = 'create' then
    if not v_patch ? (case p_etype when 'project' then 'name' else 'title' end)
       or (p_etype = 'task' and not v_patch ? 'project_id') then
      raise exception 'invalid_patch' using errcode = 'NXO01';
    end if;
    execute format('select to_jsonb(t) from public.%I t where t.id = $1', v_tbl) into v_cur using p_eid;
    if v_cur is not null then
      if (v_cur ->> 'owner_id')::uuid <> p_user then raise exception 'not_found' using errcode = 'NXO01'; end if;
      v_ver := (v_cur ->> 'version')::bigint; v_row := v_cur;
      execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', v_tbl) into v_norm using v_patch;
      v_fields := coalesce((select array_agg(e.key order by e.key) from jsonb_object_keys(v_patch) e(key)
                             where (v_norm -> e.key) is distinct from (v_cur -> e.key)), '{}');
      if v_cur ->> 'deleted_at' is null and cardinality(v_fields) = 0 then
        v_status := 'applied'; v_applied_version := v_ver;
      else
        v_status := 'conflict'; v_kind := 'exists';
        if v_cur ->> 'deleted_at' is not null then
          v_fields := (select array_agg(e.key order by e.key) from jsonb_object_keys(v_patch) e(key));
          v_sv := jsonb_build_object('deleted_at', v_cur -> 'deleted_at');
        else
          v_sv := (select jsonb_object_agg(f, v_cur -> f) from unnest(v_fields) f);
        end if;
        v_cv := (select jsonb_object_agg(f, v_patch -> f) from unnest(v_fields) f);
      end if;
    else
      if p_etype = 'task' then
        v_proj := (v_patch ->> 'project_id')::uuid;
        select to_jsonb(p) into v_pj from public.projects p where p.id = v_proj and p.owner_id = p_user;
        if v_pj is null then raise exception 'not_found' using errcode = 'NXO01'; end if;
        if v_pj ->> 'deleted_at' is not null then raise exception 'parent_invalid' using errcode = 'NXO01'; end if;
        if v_patch ? 'parent_id' and jsonb_typeof(v_patch -> 'parent_id') <> 'null' then
          perform nexora_private.check_parent(p_user, v_proj, (v_patch ->> 'parent_id')::uuid, p_eid);
        end if;
      end if;
      v_cols := (select string_agg(quote_ident(e.key), ', ' order by e.key) from jsonb_object_keys(v_patch) e(key));
      execute format('insert into public.%I (id, owner_id, %s) select $1, $2, %s from jsonb_populate_record(null::public.%I, $3) returning to_jsonb(%I)',
                     v_tbl, v_cols, v_cols, v_tbl, v_tbl) into v_row using p_eid, p_user, v_patch;
      v_status := 'applied'; v_applied_version := (v_row ->> 'version')::bigint;
    end if;

  else
    execute format('select to_jsonb(t) from public.%I t where t.id = $1 and t.owner_id = $2 for update', v_tbl)
      into v_cur using p_eid, p_user;
    if v_cur is null then raise exception 'not_found' using errcode = 'NXO01'; end if;
    v_ver := (v_cur ->> 'version')::bigint; v_row := v_cur;
    if v_base > v_ver then raise exception 'invalid_op' using errcode = 'NXO01'; end if;

    if p_otype = 'update' then
      if v_patch = '{}'::jsonb then
        v_status := 'applied'; v_applied_version := v_ver;
      elsif v_cur ->> 'deleted_at' is not null then
        v_status := 'conflict'; v_kind := 'edit_deleted';
        v_fields := (select array_agg(e.key order by e.key) from jsonb_object_keys(v_patch) e(key));
        v_sv := jsonb_build_object('deleted_at', v_cur -> 'deleted_at'); v_cv := v_patch;
      else
        if v_patch ? 'parent_id' and jsonb_typeof(v_patch -> 'parent_id') <> 'null' then
          perform nexora_private.check_parent(p_user, (v_cur ->> 'project_id')::uuid, (v_patch ->> 'parent_id')::uuid, p_eid);
        end if;
        execute format('select to_jsonb(jsonb_populate_record(null::public.%I, $1))', v_tbl) into v_norm using v_patch;
        for k in select e.key from jsonb_object_keys(v_patch) e(key) order by e.key loop
          if (v_norm -> k) is not distinct from (v_cur -> k) then continue; end if;   -- equal value: merges, nothing to do
          if coalesce((v_cur -> 'field_versions' ->> k)::bigint, 0) > v_base then v_conf := v_conf || k;
          else v_app := v_app || k; end if;
        end loop;
        if exists (select 1 from unnest(v_conf) c where c <> 'sort_order') then
          -- D-A: a conflicting operation applies nothing; both values are preserved in the conflict row.
          v_status := 'conflict'; v_kind := 'field'; v_fields := v_conf;
          v_sv := (select jsonb_object_agg(f, v_cur -> f) from unnest(v_conf) f);
          v_cv := (select jsonb_object_agg(f, v_patch -> f) from unnest(v_conf) f);
        else
          if cardinality(v_app) > 0 then
            v_apply := (select jsonb_object_agg(f, v_patch -> f) from unnest(v_app) f);
            v_cols := (select string_agg(quote_ident(f), ', ') from unnest(v_app) f);
            execute format('update public.%I t set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) where t.id = $2 and t.owner_id = $3 returning to_jsonb(t)',
                           v_tbl, v_cols, v_cols, v_tbl) into v_row using v_apply, p_eid, p_user;
          end if;
          v_status := 'applied'; v_applied_version := (v_row ->> 'version')::bigint;
          if cardinality(v_conf) > 0 then   -- only sort_order conflicted: D-O server wins, audited
            v_auto := true; v_kind := 'field'; v_fields := v_conf;
            v_sv := (select jsonb_object_agg(f, v_cur -> f) from unnest(v_conf) f);
            v_cv := (select jsonb_object_agg(f, v_patch -> f) from unnest(v_conf) f);
          end if;
        end if;
      end if;

    else  -- delete (tombstone: permanent, D-T)
      if v_cur ->> 'deleted_at' is not null then
        v_status := 'applied'; v_applied_version := v_ver;
      else
        if p_etype = 'task' then
          perform 1 from public.tasks c where c.owner_id = p_user and c.parent_id = p_eid and c.deleted_at is null limit 1;
        else
          perform 1 from public.tasks c where c.owner_id = p_user and c.project_id = p_eid and c.deleted_at is null limit 1;
        end if;
        if found then
          v_status := 'conflict'; v_kind := 'parent_has_live_children'; v_fields := array['deleted_at'];
          v_sv := '{"live_children": true}'::jsonb; v_cv := '{"op": "delete"}'::jsonb;
        elsif v_ver > v_base then
          v_status := 'conflict'; v_kind := 'delete_edited'; v_fields := array['deleted_at'];
          v_sv := jsonb_build_object('version', v_ver, 'field_versions', v_cur -> 'field_versions');
          v_cv := jsonb_build_object('op', 'delete', 'base_version', v_base);
        else
          execute format('update public.%I t set deleted_at = now() where t.id = $1 and t.owner_id = $2 returning to_jsonb(t)', v_tbl)
            into v_row using p_eid, p_user;
          v_status := 'applied'; v_applied_version := (v_row ->> 'version')::bigint;
        end if;
      end if;
    end if;
  end if;

  -- final, immutable result (inserted once)
  if v_status = 'conflict' or v_auto then v_cid := gen_random_uuid(); end if;
  v_result := jsonb_build_object('operation_id', p_opid, 'status', v_status, 'replayed', false);
  if v_status = 'applied' then
    v_result := v_result || jsonb_build_object('applied_version', v_applied_version, 'row', v_row);
    if v_auto then v_result := v_result || jsonb_build_object('conflict_id', v_cid, 'auto_resolved', true); end if;
  else
    v_result := v_result || jsonb_build_object('conflict_id', v_cid, 'row', v_row);
  end if;
  insert into public.sync_operations(user_id, operation_id, device_id, entity_type, entity_id, op_type, base_version, patch,
                                     request_hash, client_created_at, status, result, applied_version, server_seq)
  values (p_user, p_opid, p_device, p_etype, p_eid, p_otype, v_base, v_patch, p_hash, v_cca, v_status, v_result,
          case when v_status = 'applied' then v_applied_version end, nextval('nexora_private.change_seq'));
  if v_cid is not null then
    insert into public.sync_conflicts(id, user_id, operation_id, kind, entity_type, entity_id, fields, base_version, server_version,
                                      server_value, client_value, status, resolved_at, resolution_source, resolution_policy)
    values (v_cid, p_user, p_opid, v_kind, p_etype, p_eid, v_fields, coalesce(v_base, 0), v_ver, v_sv, v_cv,
            case when v_auto then 'resolved_server' else 'open' end, case when v_auto then now() end,
            case when v_auto then 'auto_policy' end, case when v_auto then 'sort_order_server_wins' end);
  end if;
  return v_result;
end $$;

-- 4. Operation wrapper: identity, replay, sub-transaction, recording of terminal rejections.
create function nexora_private.apply_operation(p_user uuid, p_device uuid, p_op jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_opid uuid; v_eid uuid; v_etype text; v_otype text; v_hash text; v_existing public.sync_operations;
  v_err text; v_state text; v_msg text; v_result jsonb; v_base_txt text; v_base bigint; v_patch jsonb;
begin
  if jsonb_typeof(p_op) is distinct from 'object' then
    return jsonb_build_object('operation_id', null, 'status', 'rejected', 'error_code', 'invalid_op', 'replayed', false);
  end if;
  begin v_opid := (p_op ->> 'operation_id')::uuid; v_eid := (p_op ->> 'entity_id')::uuid;
  exception when others then v_opid := null; end;
  v_etype := p_op ->> 'entity_type'; v_otype := p_op ->> 'op_type';
  if v_opid is null or v_eid is null or v_etype is null or v_etype not in ('project','task')
     or v_otype is null or v_otype not in ('create','update','delete') then
    return jsonb_build_object('operation_id', v_opid, 'status', 'rejected', 'error_code', 'invalid_op', 'replayed', false);
  end if;

  v_hash := encode(sha256(convert_to(concat_ws('|', v_etype, v_eid::text, v_otype,
              coalesce(p_op ->> 'base_version', ''), coalesce((p_op -> 'patch')::text, '')), 'utf8')), 'hex');
  select * into v_existing from public.sync_operations where user_id = p_user and operation_id = v_opid;
  if found then
    if v_existing.request_hash = v_hash then return v_existing.result || '{"replayed": true}'::jsonb; end if;
    return jsonb_build_object('operation_id', v_opid, 'status', 'rejected', 'error_code', 'operation_id_reuse', 'replayed', false);
  end if;

  begin
    return nexora_private.apply_core(p_user, p_device, v_opid, v_etype, v_eid, v_otype, p_op, v_hash);
  exception when others then
    v_state := sqlstate; v_msg := sqlerrm;
    if v_state = 'NXO01' then v_err := v_msg;
    elsif v_msg = 'task parent cycle' then v_err := 'parent_invalid';
    elsif v_state = '23503' and v_msg like '%tasks_parent_id_project_id_fkey%' then v_err := 'parent_invalid';
    elsif left(v_state, 2) in ('22', '23') then v_err := 'invalid_patch';
    else raise;   -- transient or unexpected: abort the whole call, record nothing
    end if;
  end;

  -- terminal rejection: the sub-transaction rolled back, so nothing was applied; record the final result once
  v_base_txt := p_op ->> 'base_version';
  v_base := case when v_otype <> 'create' and jsonb_typeof(p_op -> 'base_version') = 'number' and v_base_txt ~ '^[1-9][0-9]{0,17}$'
                 then v_base_txt::bigint end;
  v_patch := case when jsonb_typeof(p_op -> 'patch') = 'object' and octet_length((p_op -> 'patch')::text) <= 262144
                  then p_op -> 'patch' else '{}'::jsonb end;
  v_result := jsonb_build_object('operation_id', v_opid, 'status', 'rejected', 'error_code', v_err, 'replayed', false);
  insert into public.sync_operations(user_id, operation_id, device_id, entity_type, entity_id, op_type, base_version, patch,
                                     request_hash, status, result, applied_version, server_seq)
  values (p_user, v_opid, p_device, v_etype, v_eid, v_otype, v_base, v_patch, v_hash, 'rejected', v_result, null,
          nextval('nexora_private.change_seq'));
  return v_result;
end $$;

-- 5. Entry points (called through the public wrappers below).
create function nexora_private.register_device(p_device_id uuid, p_label text) returns jsonb
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

create function nexora_private.push(p_device_id uuid, p_ops jsonb) returns jsonb
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

-- 6. Public wrappers (SECURITY INVOKER): the only client-visible RPC surface.
create function public.nexora_register_device(p_device_id uuid, p_label text default null) returns jsonb
language sql security invoker set search_path = '' as
$$ select nexora_private.register_device(p_device_id, p_label) $$;

create function public.nexora_sync_push(p_device_id uuid, p_ops jsonb) returns jsonb
language sql security invoker set search_path = '' as
$$ select nexora_private.push(p_device_id, p_ops) $$;

-- 7. Exact EXECUTE grants: nothing through PUBLIC; only the two entry points and two wrappers for authenticated.
revoke all on function nexora_private.sync_user(), nexora_private.patch_spec(text, boolean),
  nexora_private.check_parent(uuid, uuid, uuid, uuid),
  nexora_private.apply_core(uuid, uuid, uuid, text, uuid, text, jsonb, text),
  nexora_private.apply_operation(uuid, uuid, jsonb), nexora_private.register_device(uuid, text),
  nexora_private.push(uuid, jsonb), public.nexora_register_device(uuid, text), public.nexora_sync_push(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant usage on schema nexora_private to authenticated;
grant execute on function nexora_private.register_device(uuid, text), nexora_private.push(uuid, jsonb),
  public.nexora_register_device(uuid, text), public.nexora_sync_push(uuid, jsonb) to authenticated;
