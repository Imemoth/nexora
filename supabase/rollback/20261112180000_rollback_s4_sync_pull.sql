-- Rollback of S4 (20261112180000_nexora_sync_pull.sql): restores the S3 catalog exactly. Not a migration.
-- Dropping sync_conflicts.change_seq and devices.last_pull_at loses only derived ordering/diagnostic data.
drop function public.nexora_sync_pull(uuid, bigint, int);
drop function nexora_private.pull(uuid, bigint, int);
drop trigger sync_conflicts_seq on public.sync_conflicts;
drop function nexora_private.guard_conflict_seq();
drop index public.sync_conflicts_user_seq_idx;
alter table public.sync_conflicts drop column change_seq;
alter table public.devices drop column last_pull_at;
