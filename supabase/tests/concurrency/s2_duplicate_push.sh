#!/usr/bin/env bash
# Multi-session tests for S2 idempotency under concurrency (disposable LOCAL server only; commits data).
# A: two sessions push the SAME operation concurrently -> applied once, the second gets the stored result (replayed).
# B: NEGATIVE CONTROL: with the per-user lock removed from push, the second session does NOT get a clean replay.
# C: a different user is not blocked while user A holds the lock (no cross-user contention).
set -uo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/../.."
REAL="${1:-nx_test}"; CTRL="${REAL}_s2nolock"
PS="psql -q -tA -v ON_ERROR_STOP=0"
newid() { cat /proc/sys/kernel/random/uuid; }

build_control() {
  $PS -d postgres -c "drop database if exists $CTRL" -c "create database $CTRL" >/dev/null
  sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_s2.sql
  $PS -d "$CTRL" -f /tmp/_boot_s2.sql >/dev/null
  for f in migrations/*.sql; do
    case "$f" in *_nexora_sync_push.sql|*_nexora_sync_throttle.sql|*_nexora_sync_response_bound.sql) sed 's/perform nexora_private.lock_user(v_user);/null;/' "$f" | $PS -d "$CTRL" >/dev/null;;
                 *) $PS -d "$CTRL" -f "$f" >/dev/null;; esac
  done
  # the throttle's counter row lock would serialize writers too; neutralize it so only the per-user lock is under test
  $PS -d "$CTRL" -c "create or replace function nexora_private.throttle(p_user uuid, p_kind text, p_ops int) returns void language sql security definer set search_path = '' as 'select 1'" >/dev/null
  [[ "$($PS -d "$CTRL" -c "select count(*) from pg_proc where proname='push' and prosrc like '%lock_user%'")" == "0" ]] || { echo "control not built"; exit 3; }
}

claims() { echo "select set_config('request.jwt.claims','{\"sub\":\"$1\",\"role\":\"authenticated\",\"is_anonymous\":false}', false); set role authenticated;"; }

setup_user() {  # $1 db, $2 user, $3 device
  $PS -d "$1" -c "insert into auth.users(id) values ('$2');" >/dev/null
  $PS -d "$1" -c "$(claims "$2") select public.nexora_register_device('$3', null);" >/dev/null
}

run_duplicate() {  # $1 db ; prints "s1=<json> | s2=<json>" and sets globals
  local db=$1 A DEV DEV2 PRJ OP ops out1 out2
  A=$(newid); DEV=$(newid); DEV2=$(newid); PRJ=$(newid); OP=$(newid)
  setup_user "$db" "$A" "$DEV"
  $PS -d "$db" -c "$(claims "$A") select public.nexora_register_device('$DEV2', null);" >/dev/null   # a second device: no shared devices-row lock
  ops="[{\"operation_id\":\"$OP\",\"entity_type\":\"project\",\"entity_id\":\"$PRJ\",\"op_type\":\"create\",\"patch\":{\"name\":\"Dup\"}}]"
  ( $PS -d "$db" -c "$(claims "$A") begin; select public.nexora_sync_push('$DEV', '$ops'::jsonb); select pg_sleep(2); commit;" > /tmp/_s2_out1 2>&1 ) &
  sleep 0.7
  ( $PS -d "$db" -c "$(claims "$A") select public.nexora_sync_push('$DEV2', '$ops'::jsonb);" > /tmp/_s2_out2 2>&1 ) &
  wait
  out1=$(cat /tmp/_s2_out1); out2=$(cat /tmp/_s2_out2)
  ROWS=$($PS -d "$db" -c "select count(*) from public.sync_operations where user_id='$A' and operation_id='$OP'")
  VER=$($PS -d "$db" -c "select coalesce(max(version),0) from public.projects where id='$PRJ'")
  S1="$out1"; S2="$out2"
}

echo "== Scenario A: concurrent duplicate on the real schema (expect one application, one replay)"
run_duplicate "$REAL"
echo "s1: $(echo "$S1" | grep -o '"status": "[a-z]*"\|"replayed": [a-z]*' | tr '\n' ' ')"
echo "s2: $(echo "$S2" | grep -o '"status": "[a-z]*"\|"replayed": [a-z]*' | tr '\n' ' ')"
echo "operation rows=$ROWS entity version=$VER"
[[ "$S1" == *'"replayed": false'* && "$S1" == *'"status": "applied"'* ]] || { echo "FAIL: first session did not apply cleanly"; exit 1; }
[[ "$S2" == *'"replayed": true'* && "$S2" == *'"status": "applied"'* ]] || { echo "FAIL: second session did not get the stored result"; exit 1; }
[[ "$ROWS" == "1" && "$VER" == "1" ]] || { echo "FAIL: operation applied more than once"; exit 1; }
echo "PASS A"

echo "== Scenario B: NEGATIVE CONTROL without the push lock (expect NO clean replay)"
build_control
run_duplicate "$CTRL"
echo "s2 (control): $(echo "$S2" | head -c 200 | tr '\n' ' ')"
if [[ "$S2" == *'"replayed": true'* ]]; then echo "FAIL: control still produced a clean replay; the test is not sensitive"; exit 1; fi
echo "PASS B (the control diverges, so scenario A detects a missing lock)"

echo "== Scenario C: another user is not blocked while user A holds the lock"
A=$(newid); DA=$(newid); B=$(newid); DB=$(newid)
setup_user "$REAL" "$A" "$DA"; setup_user "$REAL" "$B" "$DB"
opsA="[{\"operation_id\":\"$(newid)\",\"entity_type\":\"project\",\"entity_id\":\"$(newid)\",\"op_type\":\"create\",\"patch\":{\"name\":\"A\"}}]"
opsB="[{\"operation_id\":\"$(newid)\",\"entity_type\":\"project\",\"entity_id\":\"$(newid)\",\"op_type\":\"create\",\"patch\":{\"name\":\"B\"}}]"
( $PS -d "$REAL" -c "$(claims "$A") begin; select public.nexora_sync_push('$DA', '$opsA'::jsonb); select pg_sleep(2.5); commit;" >/dev/null 2>&1 ) &
sleep 0.7
start=$(date +%s%N)
outB=$($PS -d "$REAL" -c "$(claims "$B") select public.nexora_sync_push('$DB', '$opsB'::jsonb);" 2>&1)
ms=$(( ($(date +%s%N) - start) / 1000000 ))
wait
echo "user B push returned in ${ms}ms: $(echo "$outB" | grep -o '"status": "[a-z]*"')"
[[ "$outB" == *'"status": "applied"'* && $ms -lt 1500 ]] || { echo "FAIL: user B was blocked by user A"; exit 1; }
echo "PASS C"
echo "ALL S2 CONCURRENCY SCENARIOS PASSED"
