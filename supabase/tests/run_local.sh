#!/usr/bin/env bash
# Builds a disposable database from the fixture + all migrations and runs every rollback suite.
# Usage: PGHOST=/tmp PGPORT=54329 PGUSER=postgres tests/run_local.sh [db_name]
# Refuses to run against anything but a local server. Never touches the hosted project.
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: PGHOST must be a local socket or localhost" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
DB="${1:-nx_test}"
P="psql -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB"
# roles are cluster-global: create only when missing
$P -d postgres -tAc "select 1 from pg_roles where rolname='anon'" | grep -q 1 && sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot.sql || cp tests/00_bootstrap_local.sql /tmp/_boot.sql
$P -d "$DB" -f /tmp/_boot.sql
for f in migrations/*.sql; do echo "migration: $f"; $P -d "$DB" -f "$f"; done
$P -d "$DB" -tAc "select 'server_version=' || current_setting('server_version')"
for t in tests/*_test.sql; do echo "== $t"; $P -d "$DB" -f "$t" | sed -n '3,4p'; done
echo "ALL SUITES PASSED on $DB"
