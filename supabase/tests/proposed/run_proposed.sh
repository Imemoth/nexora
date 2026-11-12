#!/usr/bin/env bash
# Loads the proposal(s) into a DISPOSABLE local database built from all migrations and runs their tests. Never in CI default.
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/../.."
DB="${1:-nx_proposed}"; P="psql -v ON_ERROR_STOP=1 -q"
bash tests/run_local.sh "$DB" >/dev/null
$P -d "$DB" -f proposed/completed_at_rule_option_a.sql
$P -d "$DB" -f tests/proposed/completed_at_rule_option_a_test.sql | sed -n '3,3p'
