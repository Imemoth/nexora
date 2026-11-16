#!/usr/bin/env bash
# Multi-session tests for S3/S4 under concurrency (disposable LOCAL server only; commits data).
# A: pull never skips a row (an uncommitted writer blocks a second writer; incremental pulls return everything).
#    NEGATIVE CONTROL: with the per-user lock removed the same race DOES skip a row, so the test is sensitive.
# B: two sessions resolve the same conflict (same operation id: applied once and replayed; different ids: one wins).
# C: revoking a device while that device pushes: the push waits for the revoke and is then refused.
set -uo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/../.."
REAL="${1:-nx_test}"; CTRL="${REAL}_s4nolock"
PS="psql -q -tA -v ON_ERROR_STOP=0"
newid() { cat /proc/sys/kernel/random/uuid; }
claims() { echo "select set_config('request.jwt.claims','{\"sub\":\"$1\",\"role\":\"authenticated\",\"is_anonymous\":false}', false); set role authenticated;"; }
lastjson() { grep -E '^\{' | tail -1; }
jget() { python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(eval(sys.argv[1]))" "$1"; }

build_control() {
  $PS -d postgres -c "drop database if exists $CTRL" -c "create database $CTRL" >/dev/null
  sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_s4.sql
  $PS -d "$CTRL" -f /tmp/_boot_s4.sql >/dev/null
  for f in migrations/*.sql; do
    case "$f" in
      *_nexora_sync_protocol_schema.sql) sed 's/perform nexora_private.lock_user(new.owner_id);/null;/; s/perform nexora_private.lock_user(old.owner_id);/null;/' "$f" | $PS -d "$CTRL" >/dev/null;;
      *_nexora_sync_push.sql|*_nexora_sync_throttle.sql|*_nexora_sync_response_bound.sql) sed 's/perform nexora_private.lock_user(v_user);/null;/' "$f" | $PS -d "$CTRL" >/dev/null;;
      # The due-time migration re-installs guard_row and register_device (with their locks): the control must lose them
      # there too, or the later definition would restore the lock and the control would stop being a control.
      *_nexora_due_time.sql) sed 's/perform nexora_private.lock_user(new.owner_id);/null;/; s/perform nexora_private.lock_user(old.owner_id);/null;/; s/perform nexora_private.lock_user(v_user);/null;/' "$f" | $PS -d "$CTRL" >/dev/null;;
      *) $PS -d "$CTRL" -f "$f" >/dev/null;;
    esac
  done
  # the throttle's counter row lock would serialize writers too; neutralize it so only the per-user lock is under test
  $PS -d "$CTRL" -c "create or replace function nexora_private.throttle(p_user uuid, p_kind text, p_ops int) returns void language sql security definer set search_path = '' as 'select 1'" >/dev/null
}
setup_user() { $PS -d "$1" -c "insert into auth.users(id) values ('$2');" >/dev/null; $PS -d "$1" -c "$(claims "$2") select public.nexora_register_device('$3', null);" >/dev/null; }
reg() { $PS -d "$1" -c "$(claims "$2") select public.nexora_register_device('$3', null);" >/dev/null; }
mkops() { local o="["; local first=1; for id in "$@"; do [[ $first -eq 0 ]] && o+=","; first=0
  o+="{\"operation_id\":\"$(newid)\",\"entity_type\":\"project\",\"entity_id\":\"$id\",\"op_type\":\"create\",\"patch\":{\"name\":\"P-${id:0:6}\"}}"; done; echo "$o]"; }
pull() { $PS -d "$1" -c "$(claims "$2") select public.nexora_sync_pull('$3', $4, 500);" 2>&1 | lastjson; }

race() {  # $1 db -> sets GOT (rows seen by two incremental pulls out of 4 created), FIRST (rows seen at the first pull)
  local db=$1 A D1 D2 D3 P1 P2 P3 P4 ops1 ops2 j1 j2 c1
  A=$(newid); D1=$(newid); D2=$(newid); D3=$(newid); P1=$(newid); P2=$(newid); P3=$(newid); P4=$(newid)
  setup_user "$db" "$A" "$D1"; reg "$db" "$A" "$D2"; reg "$db" "$A" "$D3"
  ops1=$(mkops "$P1" "$P2" "$P3"); ops2=$(mkops "$P4")
  ( $PS -d "$db" -c "$(claims "$A") begin; select public.nexora_sync_push('$D1', '$ops1'::jsonb); select pg_sleep(3); commit;" >/dev/null 2>&1 ) &
  sleep 0.8
  ( $PS -d "$db" -c "$(claims "$A") select public.nexora_sync_push('$D3', '$ops2'::jsonb);" >/dev/null 2>&1 ) &
  sleep 1.0
  j1=$(pull "$db" "$A" "$D2" 0)
  FIRST=$(echo "$j1" | jget "len(d['changes'])")
  c1=$(echo "$j1" | jget "d['next_cursor']")
  wait
  j2=$(pull "$db" "$A" "$D2" "$c1")
  GOT=$(( FIRST + $(echo "$j2" | jget "len(d['changes'])") ))
  ORDER_OK=$(echo "$j2" | jget "[c['row']['change_seq'] for c in d['changes']] == sorted(c['row']['change_seq'] for c in d['changes'])")
}

echo "== Scenario A: pull during concurrent writers never skips a row"
race "$REAL"
echo "real schema: first pull saw $FIRST rows, incremental pulls saw $GOT of 4 (ordered=$ORDER_OK)"
[[ "$GOT" == "4" && "$FIRST" == "0" && "$ORDER_OK" == "True" ]] || { echo "FAIL: pull skipped or saw uncommitted rows"; exit 1; }
echo "PASS A"
echo "== Scenario A-control: NEGATIVE CONTROL without the per-user lock (expect a skipped row)"
build_control
race "$CTRL"
echo "control: first pull saw $FIRST rows, incremental pulls saw $GOT of 4"
[[ "$GOT" -lt 4 ]] || { echo "FAIL: control did not skip a row; the test is not sensitive"; exit 1; }
echo "PASS A-control (without the lock a row is skipped, so scenario A proves the lock discipline)"

mkconflict() {  # $1 db $2 user $3 dev1 $4 dev2 $5 project id -> CID
  local db=$1 A=$2 D1=$3 D2=$4 P=$5
  $PS -d "$db" -c "$(claims "$A") select public.nexora_sync_push('$D1', '[{\"operation_id\":\"$(newid)\",\"entity_type\":\"project\",\"entity_id\":\"$P\",\"op_type\":\"create\",\"patch\":{\"name\":\"N\"}}]'::jsonb);" >/dev/null
  $PS -d "$db" -c "$(claims "$A") select public.nexora_sync_push('$D1', '[{\"operation_id\":\"$(newid)\",\"entity_type\":\"project\",\"entity_id\":\"$P\",\"op_type\":\"update\",\"base_version\":1,\"patch\":{\"name\":\"Theirs\"}}]'::jsonb);" >/dev/null
  CID=$($PS -d "$db" -c "$(claims "$A") select public.nexora_sync_push('$D2', '[{\"operation_id\":\"$(newid)\",\"entity_type\":\"project\",\"entity_id\":\"$P\",\"op_type\":\"update\",\"base_version\":1,\"patch\":{\"name\":\"Mine\"}}]'::jsonb);" 2>&1 | lastjson | jget "d['results'][0]['conflict_id']")
}

echo "== Scenario B: concurrent resolutions"
A=$(newid); D1=$(newid); D2=$(newid); setup_user "$REAL" "$A" "$D1"; reg "$REAL" "$A" "$D2"
mkconflict "$REAL" "$A" "$D1" "$D2" "$(newid)"; C1=$CID
OP=$(newid)
( $PS -d "$REAL" -c "$(claims "$A") begin; select public.nexora_resolve_conflict('$D1', '$OP', '$C1', 'resolved_server'); select pg_sleep(2); commit;" > /tmp/_s3_o1 2>&1 ) &
sleep 0.7
( $PS -d "$REAL" -c "$(claims "$A") select public.nexora_resolve_conflict('$D2', '$OP', '$C1', 'resolved_server');" > /tmp/_s3_o2 2>&1 ) &
wait
r1=$(lastjson < /tmp/_s3_o1); r2=$(lastjson < /tmp/_s3_o2)
rows=$($PS -d "$REAL" -c "select count(*) from public.sync_operations where user_id='$A' and operation_id='$OP'")
echo "same op id: s1 replayed=$(echo "$r1" | jget "d['replayed']") s2 replayed=$(echo "$r2" | jget "d['replayed']") status2=$(echo "$r2" | jget "d['status']") rows=$rows"
[[ "$(echo "$r1" | jget "d['replayed']")" == "False" && "$(echo "$r2" | jget "d['replayed']")" == "True" && "$(echo "$r2" | jget "d['status']")" == "applied" && "$rows" == "1" ]] \
  || { echo "FAIL: duplicate resolution was not applied once and replayed"; exit 1; }
mkconflict "$REAL" "$A" "$D1" "$D2" "$(newid)"; C2=$CID
OPA=$(newid); OPB=$(newid)
( $PS -d "$REAL" -c "$(claims "$A") begin; select public.nexora_resolve_conflict('$D1', '$OPA', '$C2', 'resolved_client'); select pg_sleep(2); commit;" > /tmp/_s3_o1 2>&1 ) &
sleep 0.7
( $PS -d "$REAL" -c "$(claims "$A") select public.nexora_resolve_conflict('$D2', '$OPB', '$C2', 'resolved_server');" > /tmp/_s3_o2 2>&1 ) &
wait
r1=$(lastjson < /tmp/_s3_o1); r2=$(lastjson < /tmp/_s3_o2)
st=$($PS -d "$REAL" -c "select status from public.sync_conflicts where id='$C2'")
echo "different ids: s1=$(echo "$r1" | jget "d['status']") s2=$(echo "$r2" | jget "d['status']")/$(echo "$r2" | jget "d.get('error_code')") conflict=$st"
[[ "$(echo "$r1" | jget "d['status']")" == "applied" && "$(echo "$r2" | jget "d.get('error_code')")" == "conflict_not_open" && "$st" == "resolved_client" ]] \
  || { echo "FAIL: concurrent different resolutions were not serialized"; exit 1; }
echo "PASS B"

echo "== Scenario C: revoking a device while it pushes"
A=$(newid); D1=$(newid); D2=$(newid); setup_user "$REAL" "$A" "$D1"; reg "$REAL" "$A" "$D2"
PRJ=$(newid)
( $PS -d "$REAL" -c "$(claims "$A") begin; select public.nexora_revoke_device('$D1', '$D2'); select pg_sleep(2); commit;" > /tmp/_s3_o1 2>&1 ) &
sleep 0.7
start=$(date +%s%N)
out=$($PS -d "$REAL" -c "$(claims "$A") select public.nexora_sync_push('$D2', '$(mkops "$PRJ")'::jsonb);" 2>&1)
ms=$(( ($(date +%s%N) - start) / 1000000 ))
wait
n=$($PS -d "$REAL" -c "select count(*) from public.projects where id='$PRJ'")
echo "push by the revoked device returned after ${ms}ms: $(echo "$out" | grep -o 'device_invalid' | head -1) rows=$n"
[[ "$out" == *device_invalid* && "$n" == "0" && $ms -gt 900 ]] || { echo "FAIL: the revoked device was not refused after waiting for the revoke"; exit 1; }
echo "PASS C"
echo "ALL S3/S4 CONCURRENCY SCENARIOS PASSED"
