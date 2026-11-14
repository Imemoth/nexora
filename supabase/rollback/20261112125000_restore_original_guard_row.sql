-- ROLLBACK for 20261112125000_nexora_fix_projects_update_guard.sql. NOT a migration; never run by
-- supabase/tests/run_local.sh. Restores nexora_private.guard_row() to the definition applied by
-- 20261112120132 (hosted md5 of pg_get_functiondef: 6deb218ebcdc28a01fda4ec384046f27, 1151 chars).
-- WARNING: this restores the KNOWN DEFECT (any UPDATE on public.projects fails with 42703). Use it only
-- if the fix itself causes a worse regression. Hosted use needs separate owner approval.
CREATE OR REPLACE FUNCTION nexora_private.guard_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end $function$;

REVOKE EXECUTE ON FUNCTION nexora_private.guard_row() FROM PUBLIC, anon, authenticated;
