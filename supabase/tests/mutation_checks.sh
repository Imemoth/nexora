#!/usr/bin/env bash
# Mutation checks for S2: each mutation deliberately breaks the S2 migration in one security- or
# correctness-relevant way; the S2 suites MUST fail for every one. Disposable LOCAL server only.
set -uo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
PFX="${1:-nx_mut}"; PS="psql -q -tA -v ON_ERROR_STOP=0"
rm -f /tmp/_mut_*.sql
python3 - <<'PY'
import re,json
import glob
def read(key): return open(glob.glob(f'migrations/*_nexora_{key}.sql')[0]).read()
srcs={k: read(k) for k in ('sync_push','sync_resolve_revoke','sync_pull','sync_throttle','sync_response_bound','s9_revoke_direct_writes','due_time')}
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
 # ---- S3 (resolve, revoke, tree delete) and S4 (pull)
 ("resolve ignores conflict ownership", "select * into v_c from public.sync_conflicts where id = p_conflict_id and user_id = v_user;", "select * into v_c from public.sync_conflicts where id = p_conflict_id;", "sync_resolve_revoke"),
 ("resolve allows client strategy on a deleted entity", "elsif p_c.kind in ('field', 'exists') and not v_deleted then", "elsif p_c.kind in ('field', 'exists', 'edit_deleted') then", "sync_resolve_revoke"),
 ("resolution never closes the conflict", "update public.sync_conflicts set status = v_cstatus, resolved_at = now(), resolution_source = 'user',\n         resolution_operation_id = p_opid where id = p_c.id;", "null;", "sync_resolve_revoke"),
 ("resolve replay skipped", "if v_ex.op_type = 'resolve' and v_ex.request_hash = v_hash then", "if false then", "sync_resolve_revoke"),
 ("recreate copy accepts a live entity", "if not (v_deleted and p_c.kind in ('edit_deleted', 'exists')) or p_c.client_value ? 'tree' then", "if p_c.client_value ? 'tree' then", "sync_resolve_revoke"),
 ("tree delete ignores live descendants missing from the manifest", "if cardinality(v_missing) > 0 then", "if false then", "sync_resolve_revoke"),
 ("tree delete ignores edited descendants", "if v_edited is not null then", "if false then", "sync_resolve_revoke"),
 ("tree manifest may list entities outside the subtree", "if exists (select 1 from unnest(v_ids) x where not (x = any(v_all))) then", "if false then", "sync_resolve_revoke"),
 ("revoke does not check the calling device", "if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;\n  select * into v_dev", "if false then raise exception 'device_invalid' using errcode = 'NX001'; end if;\n  select * into v_dev", "sync_resolve_revoke"),
 ("revoke accepts another user's device", "select * into v_dev from public.devices where id = p_target_device_id and user_id = v_user;", "select * into v_dev from public.devices where id = p_target_device_id;", "sync_resolve_revoke"),
 ("pull returns other users' tasks", "where t.owner_id = v_user and t.change_seq > p_cursor", "where t.change_seq > p_cursor", "sync_pull"),
 ("pull accepts a cursor ahead of the server", "if p_cursor > v_high then raise exception 'invalid_cursor' using errcode = 'NX006'; end if;", "null;", "sync_pull"),
 ("pull serves revoked devices", "revoked_at is null;\n  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;\n  -- A cursor ahead", "true;\n  if not found then raise exception 'device_invalid' using errcode = 'NX001'; end if;\n  -- A cursor ahead", "sync_pull"),
 ("pull page has no byte bound", "(s.rn = 1 or s.prior + s.sz <= 1048576)", "true", "sync_pull"),
 ("conflicts are not stamped into the change stream", "new.change_seq := nextval('nexora_private.change_seq');", "new.change_seq := 0;", "sync_pull"),
 ("pull skips the limit", "(s.rn <= v_limit and", "(true and", "sync_pull"),
 ("batch size limit removed", "if n > 100 then raise exception 'batch_too_large' using errcode = 'NX003'; end if;", "null;"),
 # ---- S10 throttle, response bound; S9 direct-write revocation
 ("throttle never refuses", "if v_calls > v_lim or (p_kind = 'write' and v_ops > v_pol.write_ops_per_minute) then", "if false then", "sync_throttle"),
 ("operation budget ignored", " or (p_kind = 'write' and v_ops > v_pol.write_ops_per_minute)", "", "sync_throttle"),
 ("pull and write calls share one counter", "values (p_user, v_b, p_kind, 1,", "values (p_user, v_b, 'write', 1,", "sync_throttle"),
 ("pull is not throttled", "perform nexora_private.throttle(v_user, 'pull', 0);", "null;", "sync_throttle"),
 ("push is not throttled", "perform nexora_private.throttle(v_user, 'write', n);", "null;", "sync_throttle"),
 ("push throttle weighs zero operations", "perform nexora_private.throttle(v_user, 'write', n);", "perform nexora_private.throttle(v_user, 'write', 0);", "sync_throttle"),
 ("resolve is not throttled", "perform nexora_private.throttle(v_user, 'write', 1);", "null;", "sync_throttle"),
 ("throttle is callable by authenticated", "revoke all on function nexora_private.throttle(uuid, text, int) from public, anon, authenticated, service_role;", "grant execute on function nexora_private.throttle(uuid, text, int) to authenticated;", "sync_throttle"),
 ("rate policy writable by authenticated", "revoke all on nexora_private.rate_policy, nexora_private.rate_bucket from public, anon, authenticated, service_role;", "revoke all on nexora_private.rate_policy, nexora_private.rate_bucket from public, anon, authenticated, service_role;\ngrant select, insert, update on nexora_private.rate_policy, nexora_private.rate_bucket to authenticated;", "sync_throttle"),
 ("response bound removed", "if n > 1 and octet_length(jsonb_build_object('results', v_results)::text) > 2097152 then", "if false then", "sync_response_bound"),
 ("response bound far too high", "> 2097152 then", "> 2097152000 then", "sync_response_bound"),
 ("S9 forgets the tasks table", "on public.projects, public.tasks, public.project_members", "on public.projects, public.project_members", "s9_revoke_direct_writes"),
 ("S9 leaves UPDATE granted", "revoke insert, update, delete, truncate, references, trigger", "revoke insert, delete, truncate, references, trigger", "s9_revoke_direct_writes"),
 ("S9 leaves INSERT granted", "revoke insert, update, delete, truncate, references, trigger", "revoke update, delete, truncate, references, trigger", "s9_revoke_direct_writes"),
 ("S9 also revokes SELECT", "revoke insert, update, delete, truncate, references, trigger", "revoke select, insert, update, delete, truncate, references, trigger", "s9_revoke_direct_writes"),
]
out=[]
files=[]
for i,m in enumerate(muts):
    name,old,new=m[0],m[1],m[2]
    # a mutation applies to every migration that contains the text (apply_core lives in S2 and, replaced, in S3 and in due_time: the last definition wins, so it must be mutated too)
    keys=[k for k in srcs if srcs[k].count(old)>=1]
    assert keys and (len(m)<=3 or m[3] in keys),(name,[(k,srcs[k].count(old)) for k in srcs])
    assert all(srcs[k].count(old)>=1 for k in keys),(name,)
    for k in keys: open(f'/tmp/_mut_{i}_{k}.sql','w').write(srcs[k].replace(old,new))   # every occurrence
    out.append(name); files.append(keys)
open('/tmp/_mut_names.json','w').write(json.dumps(out))
open('/tmp/_mut_files.json','w').write(json.dumps(files))
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
    key=$(basename "$f" .sql | sed 's/^[0-9]*_nexora_//')
    if [[ -f /tmp/_mut_${i}_${key}.sql ]]; then $PS -d "$db" -f /tmp/_mut_${i}_${key}.sql >/dev/null 2>&1; else $PS -d "$db" -f "$f" >/dev/null 2>&1; fi
  done
  failed=""
  for t in s2_auth_grants_test s2_device_test s2_apply_test s2_push_test s2_contract_test s2_security_direct_test s3_resolve_test s3_tree_delete_test s3_revoke_test s4_pull_test s10_throttle_test s10_response_bound_test s9_direct_writes_test; do
    if psql -q -v ON_ERROR_STOP=1 -d "$db" -f tests/$t.sql >/dev/null 2>/tmp/_mut_err; then :; else failed="$failed $t"; fi
  done
  $PS -d postgres -c "drop database if exists $db" >/dev/null 2>&1
  if [[ -n "$failed" ]]; then caught=$((caught+1)); echo "CAUGHT  [$i] $name  (failed:$failed)";
  else missed=$((missed+1)); echo "MISSED  [$i] $name  <-- the suites did not detect this mutation"; fi
done
echo "mutations caught=$caught missed=$missed of $n"
[[ $missed -eq 0 ]]
