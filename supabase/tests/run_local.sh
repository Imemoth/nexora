#!/usr/bin/env bash
# Builds a disposable database from the fixture + all migrations and runs every rollback suite.
# Order (S9 is last on purpose): migrations up to and including the response bound (186000), then the LEGACY suites that
# write the synchronized tables directly as `authenticated` (they need the pre-S9 grants), then the S9 migration, then
# every other suite on the final state.
# Usage: PGHOST=/tmp PGPORT=54329 PGUSER=postgres tests/run_local.sh [db_name]
# Refuses to run against anything but a local server. Never touches the hosted project.
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: PGHOST must be a local socket or localhost" >&2; exit 2;; esac
cd "$(dirname "$0")/.."
DB="${1:-nx_test}"
P="psql -v ON_ERROR_STOP=1 -q"
S9=migrations/20261112190000_nexora_s9_revoke_direct_writes.sql
LEGACY="tests/fix_projects_update_guard_test.sql tests/rls_and_contract_test.sql tests/s1_sync_schema_test.sql tests/s2_pre_s9_grants_test.sql"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB"
# roles are cluster-global: create only when missing
$P -d postgres -tAc "select 1 from pg_roles where rolname='anon'" | grep -q 1 && sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot.sql || cp tests/00_bootstrap_local.sql /tmp/_boot.sql
$P -d "$DB" -f /tmp/_boot.sql
for f in migrations/*.sql; do [[ "$f" == "$S9" ]] && continue; echo "migration: $f"; $P -d "$DB" -f "$f"; done
$P -d "$DB" -tAc "select 'server_version=' || current_setting('server_version')"
echo "--- pre-S9 phase: legacy suites"
for t in $LEGACY; do echo "== $t"; $P -d "$DB" -f "$t" | sed -n '3,4p'; done
echo "--- S9 migration"; echo "migration: $S9"; $P -d "$DB" -f "$S9"
echo "--- final state: every other suite"
for t in tests/*_test.sql; do case " $LEGACY " in *" $t "*) continue;; esac; echo "== $t"; $P -d "$DB" -f "$t" | sed -n '3,4p'; done
echo "ALL SUITES PASSED on $DB"
