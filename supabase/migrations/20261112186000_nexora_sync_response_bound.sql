-- S10b: bounded push response. A push whose serialized response exceeds 2,097,152 bytes and that carries more than one
-- operation is refused with NX004 payload_too_large; the call rolls back and nothing is recorded, and the client already
-- halves its batch on NX004. A single operation is always answered. The response echoes full entity rows, so without this
-- bound the response could be far larger than the (1 MiB) request. Replaces only nexora_private.push.
-- Rollback: supabase/rollback/20261112186000_rollback_sync_response_bound.sql. Local and CI tested; NOT applied to hosted.
create or replace function nexora_private.push(p_device_id uuid, p_ops jsonb) returns jsonb
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
  perform nexora_private.throttle(v_user, 'write', n);
  perform nexora_private.lock_user(v_user);
  perform 1 from public.devices where id = p_device_id and user_id = v_user and revoked_at is null;
  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;
  update public.devices set last_push_at = now(), last_seen_at = now() where id = p_device_id;
  for i in 0 .. n - 1 loop
    v_results := v_results || jsonb_build_array(nexora_private.apply_operation(v_user, p_device_id, p_ops -> i));
  end loop;
  -- Response bound: one call never returns more than 2 MiB. A single operation is always answered (the client then
  -- cannot make progress by halving further); a larger batch is refused as a whole and records nothing.
  if n > 1 and octet_length(jsonb_build_object('results', v_results)::text) > 2097152 then
    raise exception 'payload_too_large' using errcode = 'NX004';
  end if;
  return jsonb_build_object('results', v_results);
end $$;
