-- ROLLBACK for 20261112130000_nexora_sync_protocol_schema.sql (S1). NOT a migration; never run by
-- supabase/tests/run_local.sh. Restores the catalog to the post-F1 state (guard_row = F1 definition).
-- Safe ONLY before synchronization is activated: it drops S1 columns, so it aborts if any sync row
-- or any recorded field version exists. Hosted use needs separate owner approval.
do $$ begin
  if exists (select 1 from public.sync_conflicts) or exists (select 1 from public.sync_operations)
     or exists (select 1 from public.devices) then
    raise exception 'S1 rollback aborted: sync tables are not empty';
  end if;
  if exists (select 1 from public.projects where field_versions <> '{}'::jsonb)
     or exists (select 1 from public.tasks where field_versions <> '{}'::jsonb) then
    raise exception 'S1 rollback aborted: field_versions in use';
  end if;
end $$;

-- 1. guard_row back to the F1 definition first (S1's version calls lock_user, which is dropped below).
create or replace function nexora_private.guard_row() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    new.version := 1;
    new.created_at := now();
    new.deleted_at := case when new.deleted_at is null then null else now() end;
  else
    if new.id is distinct from old.id or new.owner_id is distinct from old.owner_id then
      raise exception 'id and owner_id are immutable' using errcode = '42501';
    end if;
    -- Nested on purpose: projects has no project_id column.
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
  end if;
  new.updated_at := now();
  new.change_seq := nextval('nexora_private.change_seq');
  return new;
end $$;
revoke execute on function nexora_private.guard_row() from public, anon, authenticated;

-- 2. Triggers: drop the S1 ones, return the Phase 2B guards to the default (origin) firing mode.
drop trigger if exists devices_guard on public.devices;
drop trigger if exists sync_operations_append_only on public.sync_operations;
drop trigger if exists sync_operations_no_truncate on public.sync_operations;
drop trigger if exists sync_conflicts_guard on public.sync_conflicts;
drop trigger if exists sync_conflicts_no_truncate on public.sync_conflicts;
alter table public.projects enable trigger projects_guard;
alter table public.tasks enable trigger tasks_guard;
alter table public.tasks enable trigger tasks_guard_cycle;

-- 3. Foreign key back to RESTRICT.
alter table public.sync_operations drop constraint sync_operations_device_id_user_id_fkey;
alter table public.sync_operations add constraint sync_operations_device_id_user_id_fkey
  foreign key (device_id, user_id) references public.devices (id, user_id) on delete restrict;

-- 4. Indexes, columns (their check constraints and the resolution FK go with them), functions.
drop index if exists public.devices_user_idx, public.sync_operations_device_idx, public.sync_conflicts_operation_idx,
  public.sync_conflicts_resolution_op_idx, public.tasks_parent_fk_idx, public.tasks_project_owner_fk_idx;
alter table public.sync_conflicts
  drop column resolution_operation_id, drop column resolution_policy, drop column resolution_source, drop column kind;
alter table public.devices drop column last_push_at;
alter table public.projects drop column field_versions;
alter table public.tasks drop column field_versions;
drop function nexora_private.guard_device();
drop function nexora_private.guard_sync_log();
drop function nexora_private.lock_user(uuid);
drop function nexora_private.user_lock_key(uuid);
