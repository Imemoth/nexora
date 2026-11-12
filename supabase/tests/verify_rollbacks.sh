#!/usr/bin/env bash
# Proves the S3 and S4 rollbacks: build the S2 state, snapshot the catalog, apply S3 and S4, roll back S4 then S3,
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
 union all select 'grant|'||table_name||'|'||grantee||'|'||privilege_type from information_schema.role_table_grants where table_schema='public'
 order by 1"; }
$PS -d postgres -c "drop database if exists $DB" -c "create database $DB"
sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_rb.sql
roles=$($PS -d postgres -tAc "select 1 from pg_roles where rolname='anon'" || true); [[ "$roles" == "1" ]] || cp tests/00_bootstrap_local.sql /tmp/_boot_rb.sql
$PS -d "$DB" -f /tmp/_boot_rb.sql >/dev/null
for f in migrations/*.sql; do case "$f" in *_nexora_sync_resolve_revoke.sql|*_nexora_sync_pull.sql) ;; *) $PS -d "$DB" -f "$f" >/dev/null;; esac; done
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
$PS -d postgres -c "drop database if exists $DB" >/dev/null
echo "ALL ROLLBACK CHECKS PASSED"
