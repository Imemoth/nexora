#!/usr/bin/env bash
# Proves the S3, S4, throttle, response-bound and S9 rollbacks: build the S2 state, snapshot the catalog, apply S3 and S4, roll back S4 then S3,
# snapshot again, and require the catalogs to be identical. Also checks that the S3 rollback aborts (changing nothing)
# when S3-only data exists. Disposable LOCAL server only.
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
DB="${1:-nx_rb}"; PS="psql -q -tA -v ON_ERROR_STOP=1"
snap() { $PS -d "$DB" -c "
 select 'fn|'||p.oid::regprocedure::text||'|'||md5(pg_get_functiondef(p.oid))||'|'||coalesce(p.proacl::text,'') from pg_proc p where pronamespace in ('public'::regnamespace,'nexora_private'::regnamespace)
 union all select 'con|'||conrelid::regclass::text||'.'||conname||'|'||pg_get_constraintdef(oid) from pg_constraint where connamespace='public'::regnamespace
 union all select 'trg|'||tgrelid::regclass::text||'.'||tgname||'|'||pg_get_triggerdef(oid)||'|'||tgenabled::text from pg_trigger where not tgisinternal
 union all select 'col|'||table_name||'.'||column_name||'|'||data_type||'|'||coalesce(column_default,'')||'|'||is_nullable from information_schema.columns where table_schema='public'
 union all select 'idx|'||indexname||'|'||indexdef from pg_indexes where schemaname='public'
 union all select 'rel|'||n.nspname||'.'||c.relname||'|'||c.relkind::text||'|'||c.relrowsecurity::text||'|'||coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a),'') from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','nexora_private') and c.relkind in ('r','S','v')
 union all select 'pol|'||schemaname||'.'||tablename||'.'||policyname||'|'||cmd||'|'||roles::text||'|'||coalesce(qual,'')||'|'||coalesce(with_check,'') from pg_policies where schemaname in ('public','nexora_private')
 union all select 'grant|'||table_name||'|'||grantee||'|'||privilege_type from information_schema.role_table_grants where table_schema='public'
 order by 1"; }
$PS -d postgres -c "drop database if exists $DB" -c "create database $DB"
sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_rb.sql
roles=$($PS -d postgres -tAc "select 1 from pg_roles where rolname='anon'" || true); [[ "$roles" == "1" ]] || cp tests/00_bootstrap_local.sql /tmp/_boot_rb.sql
$PS -d "$DB" -f /tmp/_boot_rb.sql >/dev/null
for f in migrations/*.sql; do case "$f" in *_nexora_sync_resolve_revoke.sql|*_nexora_sync_pull.sql|*_nexora_sync_throttle.sql|*_nexora_sync_response_bound.sql|*_nexora_s9_revoke_direct_writes.sql|*_nexora_due_time.sql) ;; *) $PS -d "$DB" -f "$f" >/dev/null;; esac; done
snap > /tmp/_rb_s2.txt
$PS -d "$DB" -f migrations/20261112170000_nexora_sync_resolve_revoke.sql >/dev/null
snap > /tmp/_rb_s3.txt
$PS -d "$DB" -f migrations/20261112180000_nexora_sync_pull.sql >/dev/null
$PS -d "$DB" -f rollback/20261112180000_rollback_s4_sync_pull.sql >/dev/null
snap > /tmp/_rb_s3_back.txt
diff -u /tmp/_rb_s3.txt /tmp/_rb_s3_back.txt >/tmp/_rb_diff4.txt && echo "PASS: S4 rollback restores the S3 catalog exactly ($(wc -l < /tmp/_rb_s3.txt) catalog lines)" || { echo "FAIL: S4 rollback differs"; head -20 /tmp/_rb_diff4.txt; exit 1; }
# S3-only data blocks the S3 rollback and changes nothing
$PS -d "$DB" -c "insert into auth.users(id) values ('aaaaaaaa-0000-0000-0000-0000000000aa'); insert into public.devices(id,user_id) values ('d0000000-0000-0000-0000-0000000000aa','aaaaaaaa-0000-0000-0000-0000000000aa');
  insert into public.sync_operations(user_id,operation_id,device_id,entity_type,entity_id,op_type,request_hash,status,server_seq) values ('aaaaaaaa-0000-0000-0000-0000000000aa','c0000000-0000-0000-0000-0000000000aa','d0000000-0000-0000-0000-0000000000aa','project','e1000000-0000-0000-0000-0000000000aa','resolve','h','applied',1);" >/dev/null
if $PS -d "$DB" -f rollback/20261112170000_rollback_s3_resolve_revoke.sql >/dev/null 2>&1; then echo "FAIL: S3 rollback ran with resolve data present"; exit 1; fi
snap > /tmp/_rb_blocked.txt; diff -q /tmp/_rb_s3.txt /tmp/_rb_blocked.txt >/dev/null && echo "PASS: the S3 rollback aborts without changing anything when resolve data exists" || { echo "FAIL: aborted rollback changed the catalog"; exit 1; }
$PS -d "$DB" -c "delete from public.sync_operations where op_type='resolve'" 2>/dev/null || $PS -d "$DB" -c "alter table public.sync_operations disable trigger all; delete from public.sync_operations where op_type='resolve'; alter table public.sync_operations enable trigger all; alter table public.sync_operations enable always trigger sync_operations_append_only" >/dev/null
$PS -d "$DB" -f rollback/20261112170000_rollback_s3_resolve_revoke.sql >/dev/null
snap > /tmp/_rb_s2_back.txt
diff -u /tmp/_rb_s2.txt /tmp/_rb_s2_back.txt >/tmp/_rb_diff3.txt && echo "PASS: S3 rollback restores the S2 catalog exactly ($(wc -l < /tmp/_rb_s2.txt) catalog lines)" || { echo "FAIL: S3 rollback differs"; head -20 /tmp/_rb_diff3.txt; exit 1; }

# ---- throttle (185000), response bound (186000), S9 (190000): each rollback restores the previous catalog exactly
T=migrations/20261112185000_nexora_sync_throttle.sql; TR=rollback/20261112185000_rollback_sync_throttle.sql
B=migrations/20261112186000_nexora_sync_response_bound.sql; BR=rollback/20261112186000_rollback_sync_response_bound.sql
N=migrations/20261112190000_nexora_s9_revoke_direct_writes.sql; NR=rollback/20261112190000_rollback_s9_direct_writes.sql
$PS -d postgres -c "drop database if exists $DB" -c "create database $DB"
$PS -d "$DB" -f /tmp/_boot_rb.sql >/dev/null
for f in migrations/*.sql; do case "$f" in "$T"|"$B"|"$N"|*_nexora_due_time.sql) ;; *) $PS -d "$DB" -f "$f" >/dev/null;; esac; done
snap > /tmp/_rb_p4.txt
$PS -d "$DB" -f "$T" >/dev/null; snap > /tmp/_rb_p_t.txt
$PS -d "$DB" -f "$B" >/dev/null; snap > /tmp/_rb_p_b.txt
$PS -d "$DB" -f "$N" >/dev/null; snap > /tmp/_rb_p_n.txt
cmp -s /tmp/_rb_p_b.txt /tmp/_rb_p_n.txt && { echo "FAIL: S9 changed nothing in the catalog"; exit 1; }
$PS -d "$DB" -f "$NR" >/dev/null; snap > /tmp/_rb_p_n_back.txt
diff -u /tmp/_rb_p_b.txt /tmp/_rb_p_n_back.txt >/tmp/_rb_diff9.txt && echo "PASS: S9 rollback restores the pre-S9 catalog exactly ($(wc -l < /tmp/_rb_p_b.txt) catalog lines, incl. table ACLs)" || { echo "FAIL: S9 rollback differs"; head -20 /tmp/_rb_diff9.txt; exit 1; }
$PS -d "$DB" -f "$NR" >/dev/null; snap > /tmp/_rb_p_n_back2.txt
cmp -s /tmp/_rb_p_n_back.txt /tmp/_rb_p_n_back2.txt && echo "PASS: the S9 rollback is idempotent" || { echo "FAIL: S9 rollback not idempotent"; exit 1; }
$PS -d "$DB" -f "$N" >/dev/null; snap > /tmp/_rb_p_n_again.txt
cmp -s /tmp/_rb_p_n.txt /tmp/_rb_p_n_again.txt && echo "PASS: S9 re-applies to the identical catalog (idempotent forward)" || { echo "FAIL: S9 re-apply differs"; exit 1; }
$PS -d "$DB" -f "$NR" >/dev/null
$PS -d "$DB" -f "$BR" >/dev/null; snap > /tmp/_rb_p_b_back.txt
diff -u /tmp/_rb_p_t.txt /tmp/_rb_p_b_back.txt >/tmp/_rb_diffb.txt && echo "PASS: response-bound rollback restores the throttled push exactly ($(wc -l < /tmp/_rb_p_t.txt) catalog lines)" || { echo "FAIL: response-bound rollback differs"; head -20 /tmp/_rb_diffb.txt; exit 1; }
$PS -d "$DB" -f "$TR" >/dev/null; snap > /tmp/_rb_p_t_back.txt
diff -u /tmp/_rb_p4.txt /tmp/_rb_p_t_back.txt >/tmp/_rb_difft.txt && echo "PASS: throttle rollback restores the S4 catalog exactly ($(wc -l < /tmp/_rb_p4.txt) catalog lines)" || { echo "FAIL: throttle rollback differs"; head -20 /tmp/_rb_difft.txt; exit 1; }
# forward again after full rollback proves the rollbacks leave no residue (tables dropped, functions restored)
$PS -d "$DB" -f "$T" >/dev/null; $PS -d "$DB" -f "$B" >/dev/null; $PS -d "$DB" -f "$N" >/dev/null; snap > /tmp/_rb_p_final.txt
cmp -s /tmp/_rb_p_n.txt /tmp/_rb_p_final.txt && echo "PASS: full rollback then re-apply reaches the identical final catalog" || { echo "FAIL: re-apply after rollback differs"; exit 1; }
$PS -d postgres -c "drop database if exists $DB" >/dev/null
echo "ALL ROLLBACK CHECKS PASSED"
