#!/usr/bin/env bash
# Proves, on a disposable LOCAL server, that the due-time migration (20261116100000) is additive and reversible:
#  1. a populated database (users, projects, tasks with and without a date) is unchanged by the migration: same row
#     count, same values, due_time NULL everywhere, nothing dropped;
#  2. the rollback restores the previous catalog EXACTLY (functions, constraints, triggers, columns, indexes, grants);
#  3. applying the migration again after a rollback works (re-run safety).
# Usage: PGHOST=/tmp/pg PGPORT=54329 PGUSER=postgres tests/verify_due_time_migration.sh [db_name]
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
DB="${1:-nx_dtm}"; PS="psql -q -tA -v ON_ERROR_STOP=1"
M=migrations/20261116100000_nexora_due_time.sql; R=rollback/20261116100000_rollback_due_time.sql
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
rows() { $PS -d "$DB" -c "select id, project_id, title, due_date, version, field_versions::text from public.tasks order by id"; }
$PS -d postgres -c "drop database if exists $DB" -c "create database $DB"
$PS -d postgres -tAc "select 1 from pg_roles where rolname='anon'" | grep -q 1 && sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_dt.sql || cp tests/00_bootstrap_local.sql /tmp/_boot_dt.sql
$PS -d "$DB" -f /tmp/_boot_dt.sql >/dev/null
for f in migrations/*.sql; do [[ "$f" == "$M" ]] && continue; $PS -d "$DB" -f "$f" >/dev/null; done
$PS -d "$DB" >/dev/null <<'SQL'
insert into auth.users(id) values ('aaaaaaaa-0000-0000-0000-000000000001');
insert into public.projects(id, owner_id, name) values ('e1000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Existing');
insert into public.tasks(id, project_id, owner_id, title, due_date) values
 ('e2000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Dated','2026-11-20'),
 ('e2000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Undated',null);
SQL
snap > /tmp/_dt_before.txt; rows > /tmp/_dt_rows_before.txt
$PS -d "$DB" -f "$M" >/dev/null
rows > /tmp/_dt_rows_after.txt
diff -q /tmp/_dt_rows_before.txt /tmp/_dt_rows_after.txt >/dev/null && echo "PASS: existing task rows are byte-identical after the migration ($(wc -l < /tmp/_dt_rows_after.txt) rows)" || { echo "FAIL: rows changed"; exit 1; }
[[ "$($PS -d "$DB" -c "select count(*) from public.tasks where due_time is not null")" == "0" ]] && echo "PASS: no existing task has a time (date-only stays date-only)" || { echo "FAIL: a time appeared"; exit 1; }
[[ "$($PS -d "$DB" -c "select count(*) from public.tasks")" == "2" ]] && echo "PASS: no row lost"
snap > /tmp/_dt_after.txt
$PS -d "$DB" -f "$R" >/dev/null
snap > /tmp/_dt_back.txt
diff -u /tmp/_dt_before.txt /tmp/_dt_back.txt > /tmp/_dt_diff.txt && echo "PASS: the rollback restores the previous catalog exactly ($(wc -l < /tmp/_dt_before.txt) catalog lines)" || { echo "FAIL: rollback differs"; head -30 /tmp/_dt_diff.txt; exit 1; }
rows > /tmp/_dt_rows_back.txt; diff -q /tmp/_dt_rows_before.txt /tmp/_dt_rows_back.txt >/dev/null && echo "PASS: rows unchanged after the rollback"
$PS -d "$DB" -f "$M" >/dev/null && snap > /tmp/_dt_again.txt && diff -q /tmp/_dt_after.txt /tmp/_dt_again.txt >/dev/null && echo "PASS: applying the migration again after a rollback gives the same catalog"
# a stored time makes the rollback lose data, by design: prove it drops only the column
$PS -d "$DB" -c "update public.tasks set due_time = '09:30' where id = 'e2000000-0000-0000-0000-000000000001'" >/dev/null
$PS -d "$DB" -f "$R" >/dev/null
$PS -d "$DB" -c "select id, title, due_date from public.tasks order by id" > /tmp/_dt_cols_last.txt
[[ "$(cat /tmp/_dt_cols_last.txt)" == "$(printf 'e2000000-0000-0000-0000-000000000001|Dated|2026-11-20\ne2000000-0000-0000-0000-000000000002|Undated|')" ]] \
  && echo "PASS: rolling back with a stored time keeps every date and drops only the times (documented data loss)" \
  || { echo "FAIL: rollback with stored times changed more than the times"; cat /tmp/_dt_cols_last.txt; exit 1; }
echo "ALL DUE-TIME MIGRATION CHECKS PASSED on $DB"
