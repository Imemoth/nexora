-- Phase 2B / 2 of 3: align schema with the Dart domain model and add server-controlled
-- versioning, tombstones, cycle protection and a change cursor. Guarded: aborts if existing rows
-- would violate the new constraints (the tables were empty when this was written).

do $$ begin
  if exists (select 1 from public.tasks where status not in ('open','in_progress','done')
                or length(btrim(title)) > 200) then
    raise exception 'contract alignment aborted: existing task rows need manual review';
  end if;
end $$;

-- Wire values (see docs/architecture/data-contract.md)
alter table public.tasks drop constraint tasks_status_check;
alter table public.tasks add constraint tasks_status_check
  check (status in ('open','in_progress','review','done','archived'));
alter table public.tasks drop constraint tasks_priority_check;
alter table public.tasks add constraint tasks_priority_check
  check (priority in ('none','low','medium','high'));
alter table public.tasks alter column priority set default 'none';
alter table public.tasks drop constraint tasks_title_check;
alter table public.tasks add constraint tasks_title_check
  check (length(btrim(title)) between 1 and 200);
update public.tasks set notes = '' where notes is null;
alter table public.tasks alter column notes set default '';
alter table public.tasks alter column notes set not null;

-- Incremental-pull cursor
create schema if not exists nexora_private;
revoke all on schema nexora_private from public, anon, authenticated;
create sequence nexora_private.change_seq;
alter table public.projects add column change_seq bigint not null default 0;
alter table public.tasks    add column change_seq bigint not null default 0;
create index projects_owner_change_idx on public.projects (owner_id, change_seq);
create index tasks_owner_change_idx    on public.tasks (owner_id, change_seq);

-- Server-controlled fields. SECURITY DEFINER only so nextval() works; never callable as a function.
create function nexora_private.guard_row() returns trigger
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
    if tg_table_name = 'tasks' and new.project_id is distinct from old.project_id then
      raise exception 'task project_id is immutable' using errcode = '23514';
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

create function nexora_private.guard_task_cycle() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.parent_id is not null and (tg_op = 'INSERT' or new.parent_id is distinct from old.parent_id) then
    if exists (
      with recursive up(id, parent_id) as (
        select t.id, t.parent_id from public.tasks t where t.id = new.parent_id
        union
        select t.id, t.parent_id from public.tasks t join up on t.id = up.parent_id
      ) select 1 from up where up.id = new.id
    ) then
      raise exception 'task parent cycle' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;

revoke execute on function nexora_private.guard_row(), nexora_private.guard_task_cycle() from public, anon, authenticated;

create trigger projects_guard before insert or update on public.projects
  for each row execute function nexora_private.guard_row();
create trigger tasks_guard before insert or update on public.tasks
  for each row execute function nexora_private.guard_row();
create trigger tasks_guard_cycle before insert or update of parent_id on public.tasks
  for each row execute function nexora_private.guard_task_cycle();
