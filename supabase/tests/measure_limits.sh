#!/usr/bin/env bash
# Measures execution time and size of the protocol's worst legitimate calls on a disposable LOCAL server and asserts
# generous ceilings (CI runners are slow and shared; the ceilings guard against order-of-magnitude regressions and keep
# every call far below Supabase's default authenticated-role statement timeout of 8 s). Usage: measure_limits.sh [db]
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")"
DB="${1:-nx_meas}"; PS="psql -q -tA -v ON_ERROR_STOP=1"
$PS -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
sed '/^create role/d' 00_bootstrap_local.sql > /tmp/_boot_meas.sql
roles=$($PS -d postgres -tAc "select 1 from pg_roles where rolname='anon'" || true); [[ "$roles" == "1" ]] || cp 00_bootstrap_local.sql /tmp/_boot_meas.sql
$PS -d "$DB" -f /tmp/_boot_meas.sql >/dev/null
for f in ../migrations/*.sql; do $PS -d "$DB" -f "$f" >/dev/null; done
out=$(psql -q -v ON_ERROR_STOP=1 -d "$DB" -f measure_limits.sql 2>&1)
echo "$out" | grep -E 'MEASURE|ERROR|FAIL' | sed 's/^psql:[^ ]* //; s/NOTICE:  //'
$PS -d postgres -c "drop database if exists $DB" >/dev/null
ceil() { # name key max
  local v; v=$(echo "$out" | grep "MEASURE $1 " | sed -E "s/.* $2=([0-9]+).*/\1/")
  [[ -n "$v" ]] || { echo "FAIL: no measurement for $1"; exit 1; }
  if (( v > $3 )); then echo "FAIL: $1 $2=$v exceeds ceiling $3"; exit 1; else echo "OK:   $1 $2=$v <= $3"; fi
}
ceil push100 ms 5000;                ceil push100 response_bytes 2097152
ceil pull500 ms 3000;                ceil pull500 response_bytes 3145728
ceil resolve ms 1000
ceil tree1000 ms 8000
ceil push_largest_response ms 5000;  ceil push_largest_response response_bytes 2097152
echo "ALL LIMIT MEASUREMENTS WITHIN CEILINGS"
