-- PROPOSAL ONLY (not a migration, not applied anywhere, not part of any default test run).
-- Option A for the open owner decision "completed_at / status consistency" (wire contract section 7, item 1):
--   status = 'done'      requires completed_at IS NOT NULL
--   status <> 'done'     requires completed_at IS NULL
-- The client supplies both fields (S0 contract); the server only validates. A violating operation is
-- rejected by S2 as invalid_patch (SQLSTATE 23514 maps to that code). Existing rows are not rewritten.
-- Open question for the owner: legacy/ directly written rows that already violate the rule (hosted tasks table is empty today).
create function nexora_private.proposed_completed_at_rule() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (new.status = 'done') is distinct from (new.completed_at is not null) then
    raise exception 'completed_at_status_mismatch' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger proposed_completed_at_rule before insert or update of status, completed_at on public.tasks
  for each row execute function nexora_private.proposed_completed_at_rule();
