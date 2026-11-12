-- Phase 3 / S1: schema for the synchronization protocol. Additive. NO RPC, NO grant changes,
-- NO activation: clients keep exactly the privileges they had after Phase 2B.
-- Decisions: D-C (field-level conflicts), D-L (per-user advisory lock in the write path),
-- D-O (auditable auto-resolution), D-D (device cap), D-T (permanent tombstones).

do $$ begin
  if exists (select 1 from public.sync_conflicts) or exists (select 1 from public.sync_operations)
     or exists (select 1 from public.devices) then
    raise exception 'S1 aborted: sync tables must be empty';
  end if;
end $$;

-- 1. Per-user writer serialization (D-L). The key is derived from the owner only.
create function nexora_private.user_lock_key(p_user uuid) returns bigint
language sql immutable parallel safe set search_path = '' as
$$ select hashtextextended(p_user::text, 0) $$;

create function nexora_private.lock_user(p_user uuid) returns void
language plpgsql set search_path = '' as
$$ begin perform pg_advisory_xact_lock(nexora_private.user_lock_key(p_user)); end $$;

revoke execute on function nexora_private.user_lock_key(uuid), nexora_private.lock_user(uuid)
  from public, anon, authenticated;

-- 2. Field-level change tracking (D-C): field -> version at which it last changed.
alter table public.projects add column field_versions jsonb not null default '{}'::jsonb
  check (jsonb_typeof(field_versions) = 'object');
alter table public.tasks add column field_versions jsonb not null default '{}'::jsonb
  check (jsonb_typeof(field_versions) = 'object');

-- 3. guard_row (also FIXES a Phase 2B defect: UPDATE on public.projects raised 42703 because
--    the tasks-only project_id check was not short-circuited). Takes the owner's lock BEFORE allocating change_seq, so a user's change_seq values are
--    commit-ordered on every write path (authenticated, service_role, postgres, future RPCs).
--    A forged owner is rejected before any lock is taken, so a client cannot hold another user's lock.
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
      when 'tasks' then array['parent_id','title','notes','status','priority','due_date','completed_at','sort_order','deleted_at']
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
revoke execute on function nexora_private.guard_row() from public, anon, authenticated;

-- Guards must fire even when session_replication_role = replica.
alter table public.projects enable always trigger projects_guard;
alter table public.tasks enable always trigger tasks_guard;
alter table public.tasks enable always trigger tasks_guard_cycle;

-- 4. Conflict records: kind and auditable resolution (D-O).
alter table public.sync_conflicts
  add column kind text not null
    check (kind in ('field','edit_deleted','delete_edited','parent_deleted','parent_has_live_children','cycle','exists')),
  add column resolution_source text check (resolution_source in ('user','auto_policy')),
  add column resolution_policy text check (resolution_policy is null or resolution_policy in ('sort_order_server_wins')),
  add column resolution_operation_id uuid,
  add constraint sync_conflicts_resolution_consistent
    check ((status = 'open') = (resolution_source is null)),
  add constraint sync_conflicts_policy_only_auto
    check (resolution_policy is null or resolution_source = 'auto_policy'),
  add constraint sync_conflicts_resolution_op_fkey
    foreign key (user_id, resolution_operation_id) references public.sync_operations (user_id, operation_id);

-- The operation row of a losing client op is its audit record; make the log append-only.
-- pg_trigger_depth() > 1 allows FK cascades (account deletion) but not direct DML.
create function nexora_private.guard_sync_log() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'TRUNCATE' then
    raise exception '% is append-only', tg_table_name using errcode = '23514';
  end if;
  if tg_table_name = 'sync_operations' then
    if pg_trigger_depth() <= 1 then
      raise exception 'sync_operations is append-only' using errcode = '23514';
    end if;
    return coalesce(new, old);
  end if;
  -- sync_conflicts
  if tg_op = 'DELETE' then
    if pg_trigger_depth() <= 1 then
      raise exception 'sync_conflicts rows cannot be deleted directly' using errcode = '23514';
    end if;
    return old;
  end if;
  if old.status <> 'open' then
    raise exception 'resolved conflicts are final' using errcode = '23514';
  end if;
  if (new.id, new.user_id, new.operation_id, new.kind, new.entity_type, new.entity_id, new.fields,
      new.base_version, new.server_version, new.server_value, new.client_value, new.created_at)
     is distinct from
     (old.id, old.user_id, old.operation_id, old.kind, old.entity_type, old.entity_id, old.fields,
      old.base_version, old.server_version, old.server_value, old.client_value, old.created_at) then
    raise exception 'preserved conflict values are immutable' using errcode = '23514';
  end if;
  return new;
end $$;
revoke execute on function nexora_private.guard_sync_log() from public, anon, authenticated;

create trigger sync_operations_append_only before update or delete on public.sync_operations
  for each row execute function nexora_private.guard_sync_log();
create trigger sync_operations_no_truncate before truncate on public.sync_operations
  for each statement execute function nexora_private.guard_sync_log();
create trigger sync_conflicts_guard before update or delete on public.sync_conflicts
  for each row execute function nexora_private.guard_sync_log();
create trigger sync_conflicts_no_truncate before truncate on public.sync_conflicts
  for each statement execute function nexora_private.guard_sync_log();
alter table public.sync_operations enable always trigger sync_operations_append_only;
alter table public.sync_conflicts enable always trigger sync_conflicts_guard;

-- Deleting a device with operations stays blocked, but the check must run after cascades from auth.users.
alter table public.sync_operations drop constraint sync_operations_device_id_user_id_fkey;
alter table public.sync_operations add constraint sync_operations_device_id_user_id_fkey
  foreign key (device_id, user_id) references public.devices (id, user_id) on delete no action;

-- 5. Devices: push timestamp and a cap of 10 active devices per user (D-D).
alter table public.devices add column last_push_at timestamptz;
create function nexora_private.guard_device() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and (new.id is distinct from old.id or new.user_id is distinct from old.user_id) then
    raise exception 'device id and user are immutable' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' or (old.revoked_at is not null and new.revoked_at is null) then
    if new.revoked_at is null then
      perform nexora_private.lock_user(new.user_id);
      if (select count(*) from public.devices d
           where d.user_id = new.user_id and d.revoked_at is null and d.id is distinct from new.id) >= 10 then
        raise exception 'device limit reached' using errcode = '54000';
      end if;
    end if;
  end if;
  return new;
end $$;
revoke execute on function nexora_private.guard_device() from public, anon, authenticated;
create trigger devices_guard before insert or update on public.devices
  for each row execute function nexora_private.guard_device();
alter table public.devices enable always trigger devices_guard;

-- 6. Covering indexes for foreign keys (Performance Advisor INFO findings).
create index devices_user_idx on public.devices (user_id);
create index sync_operations_device_idx on public.sync_operations (device_id, user_id);
create index sync_conflicts_operation_idx on public.sync_conflicts (user_id, operation_id);
create index sync_conflicts_resolution_op_idx on public.sync_conflicts (user_id, resolution_operation_id)
  where resolution_operation_id is not null;
create index tasks_parent_fk_idx on public.tasks (parent_id, project_id) where parent_id is not null;
create index tasks_project_owner_fk_idx on public.tasks (project_id, owner_id);
