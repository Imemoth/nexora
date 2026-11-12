#!/usr/bin/env bash
# Mutation checks for S2: each mutation deliberately breaks the S2 migration in one security- or
# correctness-relevant way; the S2 suites MUST fail for every one. Disposable LOCAL server only.
set -uo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
PFX="${1:-nx_mut}"; PS="psql -q -tA -v ON_ERROR_STOP=0"
python3 - <<'PY'
import re,json
src=open('migrations/20261112160000_nexora_sync_push.sql').read()
muts=[
 ("anonymous identities accepted", "'is_anonymous', 'false')) = 'true'", "'is_anonymous', 'false')) = 'never'"),
 ("update ignores the owner filter", "where t.id = $1 and t.owner_id = $2 for update", "where t.id = $1 and $2 is not null for update"),
 ("replay lookup skipped", "  if found then\n    if v_existing.request_hash = v_hash", "  if false then\n    if v_existing.request_hash = v_hash"),
 ("operation_id reuse returns the stored result", "if v_existing.request_hash = v_hash then", "if true then"),
 ("auth.users.is_anonymous ignored", "if v_anon or lower(coalesce(", "if lower(coalesce("),
 ("deleted users with a valid token accepted", "if not found then raise exception 'unauthenticated' using errcode = '28000'; end if;\n  if v_anon", "if false then raise exception 'unauthenticated' using errcode = '28000'; end if;\n  if v_anon"),
 ("push accepts another user's device", "where id = p_device_id and user_id = v_user and revoked_at is null;", "where id = p_device_id and revoked_at is null;"),
 ("PUBLIC may execute apply_operation", "grant usage on schema nexora_private to authenticated;", "grant execute on function nexora_private.apply_operation(uuid, uuid, jsonb) to public;\ngrant usage on schema nexora_private to authenticated;"),
 ("anon may execute the wrappers", "public.nexora_register_device(uuid, text), public.nexora_sync_push(uuid, jsonb) to authenticated;", "public.nexora_register_device(uuid, text), public.nexora_sync_push(uuid, jsonb) to authenticated, anon;"),
 ("field conflicts never detected", "> v_base then v_conf := v_conf || k;", "> 1000000000 then v_conf := v_conf || k;"),
 ("update after tombstone allowed", "elsif v_cur ->> 'deleted_at' is not null then\n        v_status := 'conflict'; v_kind := 'edit_deleted';", "elsif false then\n        v_status := 'conflict'; v_kind := 'edit_deleted';"),
 ("create over another user's id allowed to proceed", "if (v_cur ->> 'owner_id')::uuid <> p_user then raise exception 'not_found' using errcode = 'NXO01'; end if;", "null;"),
 ("sort_order conflicts block the operation", "if exists (select 1 from unnest(v_conf) c where c <> 'sort_order') then", "if cardinality(v_conf) > 0 then"),
 ("transient errors recorded as rejections", "    else raise;   -- transient or unexpected: abort the whole call, record nothing", "    else v_err := 'invalid_patch';"),
 ("spoofable patch keys accepted", "if not (v_spec ? k) then raise exception 'invalid_patch' using errcode = 'NXO01'; end if;", "null;"),
 ("blocked_by_conflict ignored", "and c.entity_id = p_eid and c.status = 'open') then", "and c.entity_id = p_eid and c.status = 'open' and false) then"),
 ("version_before always 0", "'version_before', coalesce(v_ver, 0)", "'version_before', 0"),
 ("conflict detail object dropped", "  if v_cid is not null then\n    -- S5 local conflict mirror", "  if false then\n    -- S5 local conflict mirror"),
 ("authenticated may execute sync_user directly", "grant usage on schema nexora_private to authenticated;", "grant execute on function nexora_private.sync_user() to authenticated;\ngrant usage on schema nexora_private to authenticated;"),
 ("authenticated may create objects in nexora_private", "grant usage on schema nexora_private to authenticated;", "grant usage, create on schema nexora_private to authenticated;"),
 ("batch size limit removed", "if n > 100 then raise exception 'batch_too_large' using errcode = 'NX003'; end if;", "null;"),
]
out=[]
for i,(name,old,new) in enumerate(muts):
    assert src.count(old)==1,(name,src.count(old))
    open(f'/tmp/_mut_{i}.sql','w').write(src.replace(old,new))
    out.append(name)
open('/tmp/_mut_names.json','w').write(json.dumps(out))
PY
n=$(python3 -c "import json;print(len(json.load(open('/tmp/_mut_names.json'))))")
caught=0; missed=0
sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_mut.sql
for ((i=0;i<n;i++)); do
  name=$(python3 -c "import json;print(json.load(open('/tmp/_mut_names.json'))[$i])")
  db="${PFX}_$i"
  $PS -d postgres -c "drop database if exists $db" -c "create database $db" >/dev/null 2>&1
  $PS -d "$db" -f /tmp/_boot_mut.sql >/dev/null 2>&1
  for f in migrations/*.sql; do
    if [[ "$f" == *_nexora_sync_push.sql ]]; then $PS -d "$db" -f /tmp/_mut_$i.sql >/dev/null 2>&1; else $PS -d "$db" -f "$f" >/dev/null 2>&1; fi
  done
  failed=""
  for t in s2_auth_grants_test s2_device_test s2_apply_test s2_push_test s2_contract_test s2_security_direct_test; do
    if psql -q -v ON_ERROR_STOP=1 -d "$db" -f tests/$t.sql >/dev/null 2>/tmp/_mut_err; then :; else failed="$failed $t"; fi
  done
  $PS -d postgres -c "drop database if exists $db" >/dev/null 2>&1
  if [[ -n "$failed" ]]; then caught=$((caught+1)); echo "CAUGHT  [$i] $name  (failed:$failed)";
  else missed=$((missed+1)); echo "MISSED  [$i] $name  <-- the suites did not detect this mutation"; fi
done
echo "mutations caught=$caught missed=$missed of $n"
[[ $missed -eq 0 ]]
