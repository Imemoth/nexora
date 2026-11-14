-- ROLLBACK for 20261112160000_nexora_sync_push.sql (S2). NOT a migration; never run by run_local.sh.
-- Drops the S2 functions and the schema USAGE grant; restores the S1 catalog exactly. No table or data is touched.
-- Hosted use needs separate owner authorization.
drop function if exists public.nexora_sync_push(uuid, jsonb);
drop function if exists public.nexora_register_device(uuid, text);
drop function if exists nexora_private.push(uuid, jsonb);
drop function if exists nexora_private.register_device(uuid, text);
drop function if exists nexora_private.apply_operation(uuid, uuid, jsonb);
drop function if exists nexora_private.apply_core(uuid, uuid, uuid, text, uuid, text, jsonb, text);
drop function if exists nexora_private.check_parent(uuid, uuid, uuid, uuid);
drop function if exists nexora_private.patch_spec(text, boolean);
drop function if exists nexora_private.sync_user();
revoke usage on schema nexora_private from authenticated;
