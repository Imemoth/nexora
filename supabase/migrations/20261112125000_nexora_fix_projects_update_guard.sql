-- Standalone fix (independent of Phase 3 S1). Replaces ONLY the body of nexora_private.guard_row().
-- Defect: on UPDATE of public.projects the expression
--   tg_table_name = 'tasks' and new.project_id is distinct from old.project_id
-- is not guaranteed to short-circuit, and projects has no project_id column, so every project UPDATE
-- (rename, archive, soft delete) failed with 42703. Fix: nest the tasks-only check.
-- Everything else is byte-for-byte the function applied by 20261112120132. No grant, policy, trigger,
-- column, table or authorization change; no synchronization object.

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

-- Create-or-replace keeps the existing ACL; restated so the intent is explicit and idempotent.
revoke execute on function nexora_private.guard_row() from public, anon, authenticated;
