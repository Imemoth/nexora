#!/usr/bin/env bash
# Proves the standalone fix changes exactly one catalog object (guard_row) and nothing else,
# then runs its regression suite, then proves it composes with S1 (fix first, S1 after).
# Local/disposable server only. Usage: PGHOST=... tests/verify_minimal_fix.sh [db_prefix]
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
PFX="${1:-nx_fix}"; PS="psql -q -v ON_ERROR_STOP=1 -tA"
FIX=migrations/20261112125000_nexora_fix_projects_update_guard.sql
BASE=(migrations/20261112115809_*.sql migrations/20261112120132_*.sql migrations/20261112120149_*.sql)
S1=migrations/20261112130000_nexora_sync_protocol_schema.sql

snapshot() { $PS -d "$1" <<'SQL'
select 'fn|'||p.oid::regprocedure::text||'|'||md5(pg_get_functiondef(p.oid))||'|'||coalesce(p.proacl::text,'-') from pg_proc p where pronamespace in ('public'::regnamespace,'nexora_private'::regnamespace)
union all select 'trg|'||tgrelid::regclass::text||'|'||tgname||'|'||tgenabled::text||'|'||pg_get_triggerdef(oid) from pg_trigger where not tgisinternal
union all select 'col|'||table_name||'|'||column_name||'|'||data_type||'|'||coalesce(column_default,'-')||'|'||is_nullable from information_schema.columns where table_schema in ('public','nexora_private')
union all select 'con|'||conrelid::regclass::text||'|'||conname||'|'||pg_get_constraintdef(oid) from pg_constraint where connamespace='public'::regnamespace
union all select 'pol|'||tablename||'|'||policyname||'|'||cmd||'|'||coalesce(qual,'')||'|'||coalesce(with_check,'') from pg_policies where schemaname='public'
union all select 'acl|'||c.relname||'|'||coalesce(c.relacl::text,'-')||'|rls='||c.relrowsecurity from pg_class c where relnamespace='public'::regnamespace and relkind in ('r','S')
union all select 'idx|'||indexdef from pg_indexes where schemaname='public'
union all select 'tbl|'||table_schema||'.'||table_name from information_schema.tables where table_schema in ('public','nexora_private')
order by 1;
SQL
}
build() { # $1 db, rest = migration files
  local db=$1; shift
  $PS -d postgres -c "drop database if exists $db" -c "create database $db"
  if $PS -d postgres -c "select 1 from pg_roles where rolname='anon'" | grep -q 1; then sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_bf.sql; else cp tests/00_bootstrap_local.sql /tmp/_bf.sql; fi
  $PS -d "$db" -f /tmp/_bf.sql; for f in "$@"; do $PS -d "$db" -f "$f"; done
}

echo "== 1. catalog diff: Phase 2B state vs Phase 2B + fix"
build "${PFX}_a" "${BASE[@]}"; snapshot "${PFX}_a" > /tmp/_snap_a.txt
build "${PFX}_b" "${BASE[@]}" "$FIX"; snapshot "${PFX}_b" > /tmp/_snap_b.txt
changed=$(diff /tmp/_snap_a.txt /tmp/_snap_b.txt | grep -E '^[<>]' || true)
echo "$changed" | cut -c1-120
n=$(echo "$changed" | grep -c '^>' || true)
[[ "$n" == "1" && "$changed" == *"fn|nexora_private.guard_row()"* ]] || { echo "FAIL: fix changes more than guard_row"; exit 1; }
echo "OK: exactly one object changed (guard_row); grants, policies, triggers, columns, tables identical"

echo "== 2. regression suite on Phase 2B + fix"
$PS -d "${PFX}_b" -f tests/fix_projects_update_guard_test.sql | sed -n '1p'
$PS -d "${PFX}_b" -f tests/rls_and_contract_test.sql | sed -n '1p'

echo "== 3. composes with S1 (fix, then S1): all suites"
build "${PFX}_c" "${BASE[@]}" "$FIX" "$S1"
for t in fix_projects_update_guard_test rls_and_contract_test s1_sync_schema_test; do echo -n "$t: "; $PS -d "${PFX}_c" -f tests/$t.sql | sed -n '1p'; done
echo "MINIMAL FIX VERIFIED"
