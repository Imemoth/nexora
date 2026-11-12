#!/usr/bin/env bash
# Multi-session correctness test for D-L (per-user advisory lock + commit-ordered change_seq).
# Scenario A (real schema): a pull that runs while a writer is mid-transaction must never lose a row.
# Scenario B (NEGATIVE CONTROL): same scenario with the lock removed from guard_row MUST lose a row,
#   proving the test can detect the defect.
# Scenario C: a client forging another user's owner_id fails fast and cannot hold that user's lock.
# Needs a disposable LOCAL server and the databases built by run_local.sh. Commits data: local only.
set -euo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
cd "$(dirname "$0")/../.."
REAL="${1:-nx_s1}_pre9"; CTRL="${REAL}_nolock"   # direct table writes: both databases are built WITHOUT the S9 revocation
A=00000000-0000-0000-0000-0000000000a1; B=00000000-0000-0000-0000-0000000000b1
PS="psql -q -v ON_ERROR_STOP=1 -tA"

S9=migrations/20261112190000_nexora_s9_revoke_direct_writes.sql
build_real() {
  $PS -d postgres -c "drop database if exists $REAL" -c "create database $REAL"
  sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_r.sql
  $PS -d "$REAL" -f /tmp/_boot_r.sql
  for f in migrations/*.sql; do [[ "$f" == "$S9" ]] || $PS -d "$REAL" -f "$f"; done
}
build_control() {
  $PS -d postgres -c "drop database if exists $CTRL" -c "create database $CTRL"
  sed '/^create role/d' tests/00_bootstrap_local.sql > /tmp/_boot_c.sql
  $PS -d "$CTRL" -f /tmp/_boot_c.sql
  for f in migrations/*.sql; do
    [[ "$f" == "$S9" ]] && continue
    # negative control: remove only the lock acquisition from guard_row
    sed 's/perform nexora_private.lock_user(\(new\|old\).owner_id);/null;/' "$f" | $PS -d "$CTRL"
  done
  grep -q "null;" <(sed 's/perform nexora_private.lock_user(\(new\|old\).owner_id);/null;/' migrations/*sync_protocol_schema.sql) || { echo "control not built"; exit 3; }
}

scenario() {  # $1 = db; prints "pull1_count pull2_count total"
  local db=$1
  $PS -d "$db" <<SQL >/dev/null
delete from public.tasks; delete from public.projects; delete from auth.users where id in ('$A','$B');
insert into auth.users(id) values ('$A'),('$B');
insert into public.projects(id,owner_id,name) values ('a0000000-0000-0000-0000-000000000001','$A','P');
SQL
  local as="set role authenticated; select set_config('request.jwt.claim.sub','$A',false);"
  # writer 1: inserts then stays open 2s
  ( $PS -d "$db" -c "$as begin; insert into public.tasks(id,project_id,owner_id,title) values ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','$A','w1'); select pg_sleep(2); commit;" >/dev/null ) &
  sleep 0.6
  # writer 2 (same user, other device): inserts and commits immediately
  ( $PS -d "$db" -c "$as insert into public.tasks(id,project_id,owner_id,title) values ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','$A','w2');" >/dev/null ) &
  sleep 0.8
  # pull 1 while writer 1 is still open
  local p1; p1=$($PS -d "$db" -c "$as select coalesce(string_agg(title||':'||change_seq, ',' order by change_seq),'') from public.tasks;" | tail -1)
  local cursor; cursor=$($PS -d "$db" -c "$as select coalesce(max(change_seq),0) from public.tasks;" | tail -1)
  wait
  local p2; p2=$($PS -d "$db" -c "$as select coalesce(string_agg(title,',' order by change_seq),'') from public.tasks where change_seq > $cursor;" | tail -1)
  echo "pull1=[$p1] cursor=$cursor pull2=[$p2]"
  # complete iff w1 and w2 are each seen at least once across the two pulls
  local seen="$p1,$p2"
  if [[ "$seen" == *w1* && "$seen" == *w2* ]]; then echo COMPLETE; else echo GAP; fi
}

build_real
echo "== Scenario A: real schema (expect COMPLETE)"
outA=$(scenario "$REAL"); echo "$outA"
[[ "$outA" == *COMPLETE* ]] || { echo "FAIL: gap with lock in place"; exit 1; }

echo "== Scenario B: negative control without lock (expect GAP)"
build_control
outB=$(scenario "$CTRL"); echo "$outB"
[[ "$outB" == *GAP* ]] || { echo "FAIL: control did not reproduce the gap; the test is not sensitive"; exit 1; }

echo "== Scenario C: forged owner cannot hold or wait on another user's lock"
$PS -d "$REAL" <<SQL >/dev/null
delete from public.tasks; delete from public.projects; delete from auth.users where id in ('$A','$B');
insert into auth.users(id) values ('$A'),('$B');
insert into public.projects(id,owner_id,name) values ('a0000000-0000-0000-0000-000000000001','$A','P');
SQL
( $PS -d "$REAL" -c "set role authenticated; select set_config('request.jwt.claim.sub','$A',false); begin; update public.projects set name='held' where id='a0000000-0000-0000-0000-000000000001'; select pg_sleep(2); commit;" >/dev/null ) &
sleep 0.6
start=$(date +%s%N)
set +e
errC=$($PS -d "$REAL" -c "set role authenticated; select set_config('request.jwt.claim.sub','$B',false); set lock_timeout='1500ms'; insert into public.projects(owner_id,name) values ('$A','forged');" 2>&1)
set -e
ms=$(( ($(date +%s%N) - start) / 1000000 ))
wait
echo "forged insert returned after ${ms}ms: $(echo "$errC" | head -1)"
[[ "$errC" == *"owner mismatch"* && $ms -lt 1200 ]] || { echo "FAIL: forged owner waited on or took the victim's lock"; exit 1; }
echo "ALL CONCURRENCY SCENARIOS PASSED"
