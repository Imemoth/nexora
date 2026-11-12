#!/usr/bin/env bash
# Concurrent callers of one user get exactly `limit` successful calls per bucket; other users are unaffected; failed
# (refused) calls do not consume budget. Disposable LOCAL server only; commits data and restores the policy defaults.
set -uo pipefail
case "${PGHOST:-}" in /*|localhost|127.0.0.1) ;; *) echo "refusing: local server only" >&2; exit 2;; esac
DB="${1:-nx_test}"; PS="psql -q -tA -v ON_ERROR_STOP=0"
newid() { cat /proc/sys/kernel/random/uuid; }
claims() { echo "select set_config('request.jwt.claims','{\"sub\":\"$1\",\"role\":\"authenticated\",\"is_anonymous\":false}', false); set role authenticated;"; }
A=$(newid); B=$(newid); DA=$(newid); DB1=$(newid)
$PS -d "$DB" -c "insert into auth.users(id) values ('$A'),('$B')" >/dev/null
$PS -d "$DB" -c "$(claims "$A") select public.nexora_register_device('$DA', null);" >/dev/null
$PS -d "$DB" -c "$(claims "$B") select public.nexora_register_device('$DB1', null);" >/dev/null
$PS -d "$DB" -c "update nexora_private.rate_policy set pull_calls_per_minute = 5" >/dev/null
restore() { $PS -d "$DB" -c "update nexora_private.rate_policy set pull_calls_per_minute = 120, write_calls_per_minute = 120, write_ops_per_minute = 6000" >/dev/null; }
trap restore EXIT
# keep every call inside one bucket minute
s=$(date +%S); (( 10#$s > 45 )) && sleep $((61 - 10#$s))
rm -f /tmp/_thr_*.out
for i in $(seq 1 16); do
  ( $PS -d "$DB" -c "$(claims "$A") select public.nexora_sync_pull('$DA', 0, 10);" > /tmp/_thr_$i.out 2>&1 ) &
done
wait
ok=$(grep -l '"next_cursor"' /tmp/_thr_*.out | wc -l); refused=$(grep -l 'rate_limited' /tmp/_thr_*.out | wc -l)
echo "16 concurrent pulls with limit 5: succeeded=$ok refused=$refused"
[[ "$ok" == 5 && "$refused" == 11 ]] || { echo "FAIL: expected exactly 5 successes and 11 refusals"; exit 1; }
grep -h 'ERROR' /tmp/_thr_*.out | grep -v 'NX007\|rate_limited' && { echo "FAIL: unexpected error"; exit 1; }
cnt=$($PS -d "$DB" -c "select calls from nexora_private.rate_bucket where user_id='$A' and kind='pull' order by bucket desc limit 1")
echo "stored counter=$cnt"; [[ "$cnt" == 5 ]] || { echo "FAIL: counter must equal the number of successful calls (refused calls roll back)"; exit 1; }
# another user, same moment, unaffected
r=$($PS -d "$DB" -c "$(claims "$B") select public.nexora_sync_pull('$DB1', 0, 10);" 2>&1 | grep -c '"next_cursor"')
[[ "$r" == 1 ]] || { echo "FAIL: other user affected"; exit 1; }
echo "PASS: exactly the limit succeeds under concurrency, refusals leave the counter exact, other users unaffected"
