-- Optional time of day on a task's due date (ADR 0004, docs/architecture/decisions/0004-due-time-semantics-and-hosted-boundary.md).
-- ADDITIVE and NOT APPLIED to the hosted project: it needs the owner's separate approval of this exact file
-- (docs/operations/due-time-hosted-migration.md has the deployment sequence, rollback and verification).
--
-- What it does:
--   1. tasks.due_time (time without time zone, minute precision, NULL = date-only). A time needs a date (check).
--      The time is a floating wall-clock time: no zone, never converted. Existing rows get NULL: nothing changes.
--   2. due_time is a tracked field (field_versions, conflicts) and a patchable field: ["string", nullable].
--      The wire form is 'HH:MM'; 'HH:MM:SS' with seconds, 24:00, or a time without a date, is `invalid_patch`.
--   3. Old-client safety: when a patch changes due_date and says nothing about due_time, the stored time is cleared in
--      the same update (pair_due_time). A stale time can never survive a date change made by a client that does not know
--      the time. A client that does know it sends both fields together.
--   4. register_device also answers `features: ["due_time"]`, so a client can tell a migrated server from an old one.
-- Nothing here changes a grant, a policy, an index, a cursor or another contract. Rollback:
-- supabase/rollback/20261116100000_rollback_due_time.sql.

alter table public.tasks add column due_time time without time zone null;
alter table public.tasks add constraint tasks_due_time_needs_date
  check (due_time is null or (due_date is not null and extract(second from due_time) = 0 and due_time < time '24:00'));

create or replace function nexora_private.patch_spec(p_etype text, p_create boolean) returns jsonb
language sql immutable set search_path = '' as $$
  select case p_etype
    when 'project' then '{"name":["string",false],"description":["string",true],"color":["string",true],"is_archived":["boolean",false],"sort_order":["number",false]}'::jsonb
    else '{"parent_id":["string",true],"title":["string",false],"notes":["string",false],"status":["string",false],"priority":["string",false],"due_date":["string",true],"due_time":["string",true],"completed_at":["string",true],"sort_order":["number",false]}'::jsonb
         || case when p_create then '{"project_id":["string",false]}'::jsonb else '{}'::jsonb end
  end $$;

-- The patch to apply for a task: p_patch, plus due_time = null when it changes the date but does not mention the time
-- while the task has one. Pure; never raises.
create function nexora_private.pair_due_time(p_cur jsonb, p_patch jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select case
    when p_patch ? 'due_date' and not (p_patch ? 'due_time')
         and p_cur ->> 'due_time' is not null
         and (p_patch -> 'due_date') is distinct from (p_cur -> 'due_date')
    then p_patch || '{"due_time": null}'::jsonb
    else p_patch end $$;
revoke execute on function nexora_private.pair_due_time(jsonb, jsonb) from public, anon, authenticated;

create or replace function nexora_private.guard_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_fields text[];
  v_changed jsonb := '{}'::jsonb;
  v_old jsonb;
  v_new jsonb;
  k text;
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and new.owner_id is distinct from auth.uid() then
      raise exception 'owner mismatch' using errcode = '42501';
    end if;
    perform nexora_private.lock_user(new.owner_id);
    new.version := 1;
    new.created_at := now();
    new.deleted_at := case when new.deleted_at is null then null else now() end;
    new.field_versions := '{}'::jsonb;
  else
    perform nexora_private.lock_user(old.owner_id);
    if new.id is distinct from old.id or new.owner_id is distinct from old.owner_id then
      raise exception 'id and owner_id are immutable' using errcode = '42501';
    end if;
    -- Nested on purpose: AND does not guarantee short-circuit, and projects has no project_id column.
    if tg_table_name = 'tasks' then
      if new.project_id is distinct from old.project_id then
        raise exception 'task project_id is immutable' using errcode = '23514';
      end if;
    end if;
    if old.deleted_at is not null then
      if new.deleted_at is distinct from old.deleted_at then
        raise exception 'tombstones cannot be reverted' using errcode = '23514';
      end if;
    elsif new.deleted_at is not null then
      new.deleted_at := now();
    end if;
    new.version := old.version + 1;
    new.created_at := old.created_at;
    v_fields := case tg_table_name
      when 'tasks' then array['parent_id','title','notes','status','priority','due_date','due_time','completed_at','sort_order','deleted_at']
      else array['name','description','color','is_archived','sort_order','deleted_at'] end;
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    foreach k in array v_fields loop
      if v_new -> k is distinct from v_old -> k then
        v_changed := v_changed || jsonb_build_object(k, new.version);
      end if;
    end loop;
    new.field_versions := old.field_versions || v_changed;   -- client-supplied value is ignored
  end if;
  new.updated_at := now();
  new.change_seq := nextval('nexora_private.change_seq');
  return new;
end $$;

create or replace function nexora_private.apply_core(p_user uuid, p_device uuid, p_opid uuid, p_etype text, p_eid uuid,
                                          p_otype text, p_op jsonb, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tbl text := case p_etype when 'project' then 'projects' else 'tasks' end;
  v_spec jsonb; v_patch jsonb := '{}'::jsonb; v_base bigint; v_cca timestamptz;
  k text; val jsonb; v_cur jsonb; v_norm jsonb; v_ver bigint;
  v_status text; v_row jsonb; v_applied_version bigint;
  v_cid uuid; v_kind text; v_fields text[]; v_sv jsonb; v_cv jsonb; v_auto boolean := false;
  v_conf text[] := '{}'; v_app text[] := '{}'; v_apply jsonb; v_cols text; v_result jsonb; v_proj uuid;
  v_pj jsonb; v_tree jsonb; v_tree_n int; v_ids uuid[]; v_all uuid[]; v_live uuid[]; v_missing uuid[]; v_edited jsonb;
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
      -- S3 protocol extension: {"tree": [{"id": uuid, "base_version": n}, ...]} lists every descendant the client
      -- deletes together with the root; the server verifies the list against the live subtree and applies it
      -- atomically or not at all (it never deletes an entity the client did not list).
      if jsonb_typeof(p_op -> 'patch') <> 'object' or (select count(*) from jsonb_object_keys(p_op -> 'patch')) <> 1
         or not ((p_op -> 'patch') ? 'tree') or jsonb_typeof(p_op -> 'patch' -> 'tree') <> 'array' then
        raise exception 'invalid_op' using errcode = 'NXO01';
      end if;
      if octet_length((p_op -> 'patch')::text) > 262144 then raise exception 'payload_too_large' using errcode = 'NXO01'; end if;
      v_tree := p_op -> 'patch' -> 'tree';
      if jsonb_array_length(v_tree) > 1000 then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;
      for val in select e.value from jsonb_array_elements(v_tree) e loop
        if jsonb_typeof(val) <> 'object' or (select count(*) from jsonb_object_keys(val)) <> 2
           or not (val ? 'id' and val ? 'base_version') or jsonb_typeof(val -> 'id') <> 'string'
           or jsonb_typeof(val -> 'base_version') <> 'number' or (val ->> 'base_version') !~ '^[1-9][0-9]{0,17}$' then
          raise exception 'invalid_patch' using errcode = 'NXO01';
        end if;
        begin perform (val ->> 'id')::uuid; exception when others then raise exception 'invalid_patch' using errcode = 'NXO01'; end;
      end loop;
      v_ids := array(select (e ->> 'id')::uuid from jsonb_array_elements(v_tree) e);
      if cardinality(v_ids) <> (select count(distinct x) from unnest(v_ids) x) or p_eid = any(v_ids) then
        raise exception 'invalid_patch' using errcode = 'NXO01';
      end if;
      v_patch := p_op -> 'patch';
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
            -- Due time (ADR 0004): a date that changes while the patch says nothing about the time (an older client)
            -- must not leave the old time behind. The time is cleared as part of the same update. No conflict is
            -- raised for this: it is a consequence of the date change, not an edit of the time.
            v_pj := nexora_private.pair_due_time(v_cur, v_patch);
            if v_pj <> v_patch then v_patch := v_pj; v_app := v_app || 'due_time'::text; end if;
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
      elsif v_tree is not null then
        -- S3: atomic tree delete. Every descendant (live or already tombstoned) of the root, in this user's data.
        with recursive d(id) as (
          select t.id from public.tasks t where t.owner_id = p_user
             and ((p_etype = 'task' and t.parent_id = p_eid) or (p_etype = 'project' and t.project_id = p_eid))
          union
          select t.id from public.tasks t join d on t.parent_id = d.id where t.owner_id = p_user)
        select coalesce(array_agg(d.id), '{}') into v_all from d;
        select coalesce(array_agg(t.id), '{}') into v_live from public.tasks t
         where t.id = any(v_all) and t.deleted_at is null;
        if exists (select 1 from unnest(v_ids) x where not (x = any(v_all))) then
          raise exception 'invalid_patch' using errcode = 'NXO01';   -- lists something that is not in the subtree
        end if;
        v_missing := array(select x from unnest(v_live) x where not (x = any(v_ids)));
        if cardinality(v_missing) > 0 then
          v_status := 'conflict'; v_kind := 'parent_has_live_children'; v_fields := array['deleted_at'];
          v_sv := jsonb_build_object('live_children', to_jsonb(v_missing));
          v_cv := jsonb_build_object('op', 'delete', 'tree', to_jsonb(v_ids));
        elsif v_ver > v_base then
          v_status := 'conflict'; v_kind := 'delete_edited'; v_fields := array['deleted_at'];
          v_sv := jsonb_build_object('version', v_ver, 'field_versions', v_cur -> 'field_versions');
          v_cv := jsonb_build_object('op', 'delete', 'base_version', v_base, 'tree', to_jsonb(v_ids));
        else
          select jsonb_agg(jsonb_build_object('id', t.id, 'version', t.version, 'base_version', m.bv) order by t.id)
            into v_edited
            from public.tasks t
            join (select (e ->> 'id')::uuid id, (e ->> 'base_version')::bigint bv from jsonb_array_elements(v_tree) e) m on m.id = t.id
           where t.deleted_at is null and t.version > m.bv;
          if v_edited is not null then
            v_status := 'conflict'; v_kind := 'delete_edited'; v_fields := array['deleted_at'];
            v_sv := jsonb_build_object('edited', v_edited);
            v_cv := jsonb_build_object('op', 'delete', 'base_version', v_base, 'tree', to_jsonb(v_ids));
          else
            update public.tasks t set deleted_at = now() where t.owner_id = p_user and t.id = any(v_live) and t.deleted_at is null;
            execute format('update public.%I t set deleted_at = now() where t.id = $1 and t.owner_id = $2 returning to_jsonb(t)', v_tbl)
              into v_row using p_eid, p_user;
            v_status := 'applied'; v_applied_version := (v_row ->> 'version')::bigint;
            v_tree_n := cardinality(v_live) + 1;
          end if;
        end if;
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
  v_result := jsonb_build_object('operation_id', p_opid, 'status', v_status, 'replayed', false,
                                 'version_before', coalesce(v_ver, 0));   -- server version before this operation (0: new entity)
  if v_status = 'applied' then
    v_result := v_result || jsonb_build_object('applied_version', v_applied_version, 'row', v_row);
    if v_tree_n is not null then v_result := v_result || jsonb_build_object('tree_deleted', v_tree_n); end if;
    if v_auto then v_result := v_result || jsonb_build_object('conflict_id', v_cid, 'auto_resolved', true); end if;
  else
    v_result := v_result || jsonb_build_object('conflict_id', v_cid, 'row', v_row);
  end if;
  if v_cid is not null then
    -- S5 local conflict mirror: own-user data only (conflicts exist only on entities the caller owns)
    v_result := v_result || jsonb_build_object('conflict', jsonb_build_object(
      'kind', v_kind, 'fields', to_jsonb(v_fields), 'base_version', coalesce(v_base, 0), 'server_version', v_ver,
      'server_value', v_sv, 'client_value', v_cv, 'status', case when v_auto then 'resolved_server' else 'open' end));
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

create or replace function nexora_private.resolve_core(p_user uuid, p_device uuid, p_opid uuid, p_c public.sync_conflicts,
                                            p_resolution text, p_values jsonb, p_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tbl text := case p_c.entity_type when 'project' then 'projects' else 'tasks' end;
  v_cur jsonb; v_row jsonb; v_ver bigint; v_before bigint; v_deleted boolean; v_patch jsonb; v_spec jsonb;
  k text; val jsonb; v_cols text; v_copy uuid; v_new jsonb; v_cstatus text; v_applied bigint; v_changed boolean := false;
  v_result jsonb; v_proj jsonb;
begin
  if p_c.status <> 'open' then raise exception 'conflict_not_open' using errcode = 'NXO01'; end if;
  execute format('select to_jsonb(t) from public.%I t where t.id = $1 and t.owner_id = $2 for update', v_tbl)
    into v_cur using p_c.entity_id, p_user;
  if v_cur is null then raise exception 'not_found' using errcode = 'NXO01'; end if;
  v_ver := (v_cur ->> 'version')::bigint; v_before := v_ver; v_row := v_cur;
  v_deleted := v_cur ->> 'deleted_at' is not null;

  if p_resolution = 'resolved_server' then
    null;   -- the server state stands; the client patch is discarded (both values stay in the conflict row)
  elsif p_resolution in ('resolved_client', 'resolved_merged') then
    if p_c.client_value ? 'tree' then raise exception 'strategy_not_allowed' using errcode = 'NXO01'; end if;
    if p_c.kind in ('delete_edited', 'parent_has_live_children') then
      if p_resolution = 'resolved_merged' then raise exception 'strategy_not_allowed' using errcode = 'NXO01'; end if;
      if not v_deleted then   -- re-apply the single delete now, unless live children appeared
        if p_c.entity_type = 'task' then
          perform 1 from public.tasks c where c.owner_id = p_user and c.parent_id = p_c.entity_id and c.deleted_at is null limit 1;
        else
          perform 1 from public.tasks c where c.owner_id = p_user and c.project_id = p_c.entity_id and c.deleted_at is null limit 1;
        end if;
        if found then raise exception 'parent_has_live_children' using errcode = 'NXO01'; end if;
        execute format('update public.%I t set deleted_at = now() where t.id = $1 and t.owner_id = $2 returning to_jsonb(t)', v_tbl)
          into v_row using p_c.entity_id, p_user;
        v_changed := true;
      end if;
    elsif p_c.kind in ('field', 'exists') and not v_deleted then
      v_patch := case when p_resolution = 'resolved_client' then p_c.client_value else p_values end;
      if v_patch is null or jsonb_typeof(v_patch) <> 'object' or v_patch = '{}'::jsonb then
        raise exception 'invalid_values' using errcode = 'NXO01';
      end if;
      v_spec := nexora_private.patch_spec(p_c.entity_type, false);
      for k, val in select e.key, e.value from jsonb_each(v_patch) e loop
        if not (v_spec ? k) then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;
        if jsonb_typeof(val) = 'null' then
          if not (v_spec -> k ->> 1)::boolean then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;
        elsif jsonb_typeof(val) <> (v_spec -> k ->> 0) then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;
      end loop;
      if v_patch ? 'parent_id' and jsonb_typeof(v_patch -> 'parent_id') <> 'null' then
        perform nexora_private.check_parent(p_user, (v_cur ->> 'project_id')::uuid, (v_patch ->> 'parent_id')::uuid, p_c.entity_id);
      end if;
      if p_c.entity_type = 'task' then v_patch := nexora_private.pair_due_time(v_cur, v_patch); end if;   -- ADR 0004
      v_cols := (select string_agg(quote_ident(e.key), ', ' order by e.key) from jsonb_each(v_patch) e);
      execute format('update public.%I t set (%s) = (select %s from jsonb_populate_record(null::public.%I, $1)) where t.id = $2 and t.owner_id = $3 returning to_jsonb(t)',
                     v_tbl, v_cols, v_cols, v_tbl) into v_row using v_patch, p_c.entity_id, p_user;
      v_changed := true;
    else
      raise exception 'strategy_not_allowed' using errcode = 'NXO01';
    end if;
  elsif p_resolution = 'recreate_copy' then
    -- Tombstones are permanent (D-T): the copy is a NEW entity (client-chosen id) holding the client's intended values.
    if not (v_deleted and p_c.kind in ('edit_deleted', 'exists')) or p_c.client_value ? 'tree' then
      raise exception 'strategy_not_allowed' using errcode = 'NXO01';
    end if;
    if p_values is null or jsonb_typeof(p_values -> 'new_entity_id') is distinct from 'string' then
      raise exception 'invalid_values' using errcode = 'NXO01';
    end if;
    begin v_copy := (p_values ->> 'new_entity_id')::uuid;
    exception when others then raise exception 'invalid_values' using errcode = 'NXO01'; end;
    if exists (select 1 from public.projects where id = v_copy) or exists (select 1 from public.tasks where id = v_copy) then
      raise exception 'invalid_values' using errcode = 'NXO01';
    end if;
    v_new := v_cur || p_c.client_value;
    if p_c.entity_type = 'task' then v_new := v_new || (nexora_private.pair_due_time(v_cur, p_c.client_value) - 'due_date'); end if;
    if p_c.entity_type = 'project' then
      execute 'insert into public.projects (id, owner_id, name, description, color, is_archived, sort_order) '
              'select $1, $2, r.name, r.description, r.color, r.is_archived, r.sort_order '
              'from jsonb_populate_record(null::public.projects, $3) r returning to_jsonb(projects)'
        into v_row using v_copy, p_user, v_new;
    else
      select to_jsonb(p) into v_proj from public.projects p where p.id = (v_cur ->> 'project_id')::uuid and p.owner_id = p_user;
      if v_proj is null or v_proj ->> 'deleted_at' is not null then raise exception 'parent_invalid' using errcode = 'NXO01'; end if;
      if jsonb_typeof(v_new -> 'parent_id') = 'string' and not exists (
           select 1 from public.tasks t where t.id = (v_new ->> 'parent_id')::uuid and t.owner_id = p_user
              and t.project_id = (v_cur ->> 'project_id')::uuid and t.deleted_at is null) then
        v_new := v_new || '{"parent_id": null}'::jsonb;   -- the original parent is gone: the copy becomes a root task
      end if;
      execute 'insert into public.tasks (id, owner_id, project_id, parent_id, title, notes, status, priority, due_date, due_time, completed_at, sort_order) '
              'select $1, $2, r.project_id, r.parent_id, r.title, r.notes, r.status, r.priority, r.due_date, r.due_time, r.completed_at, r.sort_order '
              'from jsonb_populate_record(null::public.tasks, $3) r returning to_jsonb(tasks)'
        into v_row using v_copy, p_user, v_new;
    end if;
    v_changed := true;
  else
    raise exception 'invalid_request' using errcode = 'NXO01';
  end if;

  v_applied := case when v_changed then (v_row ->> 'version')::bigint end;
  v_result := jsonb_build_object('operation_id', p_opid, 'status', 'applied', 'conflict_id', p_c.id,
                                 'resolution', p_resolution, 'version_before', v_before, 'row', v_row, 'replayed', false);
  if v_applied is not null then v_result := v_result || jsonb_build_object('applied_version', v_applied); end if;
  if v_copy is not null then v_result := v_result || jsonb_build_object('copy_entity_id', v_copy); end if;
  insert into public.sync_operations(user_id, operation_id, device_id, entity_type, entity_id, op_type, base_version, patch,
                                     request_hash, status, result, applied_version, server_seq)
  values (p_user, p_opid, p_device, p_c.entity_type, p_c.entity_id, 'resolve', null,
          jsonb_build_object('conflict_id', p_c.id, 'resolution', p_resolution, 'values', coalesce(p_values, 'null'::jsonb)),
          p_hash, 'applied', v_result, v_applied, nextval('nexora_private.change_seq'));
  v_cstatus := case p_resolution when 'resolved_server' then 'resolved_server' when 'resolved_client' then 'resolved_client'
                                 when 'resolved_merged' then 'resolved_merged' else 'resolved_copy' end;
  update public.sync_conflicts set status = v_cstatus, resolved_at = now(), resolution_source = 'user',
         resolution_operation_id = p_opid where id = p_c.id;
  return v_result;
end $$;

create or replace function nexora_private.register_device(p_device_id uuid, p_label text) returns jsonb
language plpgsql security definer set search_path = '' set lock_timeout = '5s' as $$
declare v_user uuid; v_dev public.devices; v_created boolean := false; v_active int;
begin
  v_user := nexora_private.sync_user();
  perform nexora_private.throttle(v_user, 'write', 0);
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
  -- features: what this server understands beyond the base contract. A client enables an optional field only when it
  -- is listed here; an older server (or an older function) lists nothing.
  return jsonb_build_object('device_id', p_device_id, 'created', v_created, 'active_devices', v_active,
                            'features', jsonb_build_array('due_time'));
end $$;

-- Function ACLs: replacing a function keeps its owner and grants; re-assert the exact baseline anyway.
revoke execute on function nexora_private.guard_row() from public, anon, authenticated;
revoke execute on function nexora_private.apply_core(uuid, uuid, uuid, text, uuid, text, jsonb, text) from public, anon, authenticated;
revoke execute on function nexora_private.resolve_core(uuid, uuid, uuid, public.sync_conflicts, text, jsonb, text) from public, anon, authenticated;
