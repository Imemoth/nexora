#!/usr/bin/env python3
"""Hosted HTTP/JWT acceptance for the Nexora sync RPCs (real PostgREST + GoTrue; no mocks).

Credentials come only from the environment (never from files in the repo, never printed):
  NEXORA_URL, NEXORA_ANON_KEY (publishable/anon key only), NEXORA_USER_A, NEXORA_PASS_A, NEXORA_USER_B, NEXORA_PASS_B
Usage: hosted_acceptance.py [phase]   phase: main | s9 | all (default all). Writes test rows for the two given
identities only; never uses a service-role key. Prints a JSON report (no tokens, no passwords).
"""
import json, os, sys, time, uuid, urllib.request, urllib.error

URL = os.environ['NEXORA_URL'].rstrip('/')
ANON = os.environ['NEXORA_ANON_KEY']
RESULTS = []


def http(method, path, token=None, body=None, headers=None):
    h = {'apikey': ANON, 'Content-Type': 'application/json'}
    if token:
        h['Authorization'] = 'Bearer ' + token
    if headers:
        h.update(headers)
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(URL + path, data=data, method=method, headers=h)
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read(); status = r.status
    except urllib.error.HTTPError as e:
        raw = e.read(); status = e.code
    ms = (time.perf_counter() - t0) * 1000
    try:
        js = json.loads(raw) if raw else None
    except ValueError:
        js = None
    return status, js, ms, len(raw)


def login(email, pw):
    s, js, _, _ = http('POST', '/auth/v1/token?grant_type=password', body={'email': email, 'password': pw})
    assert s == 200, f'login failed {s}'
    return js['access_token'], js


def sub_of(token):
    import base64
    part = token.split('.')[1]
    return json.loads(base64.urlsafe_b64decode(part + '=' * (-len(part) % 4)))['sub']


def rpc(token, fn, body):
    return http('POST', '/rest/v1/rpc/' + fn, token, body)


def check(name, ok, detail=''):
    RESULTS.append({'test': name, 'ok': bool(ok), 'detail': str(detail)[:300]})
    print(('PASS ' if ok else 'FAIL ') + name + (f'  [{detail}]' if detail else ''), flush=True)


def op(kind, etype, eid, patch=None, base=None, opid=None):
    o = {'operation_id': opid or str(uuid.uuid4()), 'entity_type': etype, 'entity_id': eid, 'op_type': kind}
    if base is not None:
        o['base_version'] = base
    if patch is not None:
        o['patch'] = patch
    return o


def push(tok, dev, ops):
    return rpc(tok, 'nexora_sync_push', {'p_device_id': dev, 'p_ops': ops})


def err_msg(js):
    return (js or {}).get('message') if isinstance(js, dict) else None


def main_phase(ta, tb, uid_a, uid_b):
    # --- identity
    s, js, _, _ = rpc(None, 'nexora_register_device', {'p_device_id': str(uuid.uuid4())})
    check('no token: RPC refused', s in (401, 403), s)
    s, js, _, _ = rpc(ANON, 'nexora_register_device', {'p_device_id': str(uuid.uuid4())})
    check('anon-role key as bearer: RPC refused', s in (401, 403), f'{s} {err_msg(js)}')
    s, js, _, _ = rpc('not.a.jwt', 'nexora_register_device', {'p_device_id': str(uuid.uuid4())})
    check('garbage JWT refused', s in (401, 403), s)

    # --- devices
    a1, a2, b1 = (str(uuid.uuid4()) for _ in range(3))
    s, js, _, _ = rpc(ta, 'nexora_register_device', {'p_device_id': a1, 'p_label': 'accept-A1'})
    check('register device A1', s == 200 and js.get('created') is True, f'{s}')
    s, js, _, _ = rpc(ta, 'nexora_register_device', {'p_device_id': a2, 'p_label': 'accept-A2'})
    check('register device A2', s == 200 and js.get('active_devices') == 2, f'{s}')
    s, js, _, _ = rpc(ta, 'nexora_register_device', {'p_device_id': a1, 'p_label': 'accept-A1'})
    check('register is idempotent', s == 200 and js.get('created') is False, f'{s}')
    s, js, _, _ = rpc(tb, 'nexora_register_device', {'p_device_id': b1, 'p_label': 'accept-B1'})
    check('register device B1', s == 200, f'{s}')
    s, js, _, _ = rpc(tb, 'nexora_register_device', {'p_device_id': a1})
    check("cross-user: B cannot register A's device id", s != 200 and 'device_invalid' in str(err_msg(js)), f'{s} {err_msg(js)}')

    # --- project + tasks + replay
    proj = str(uuid.uuid4()); t1 = str(uuid.uuid4()); t2 = str(uuid.uuid4())
    ops = [op('create', 'project', proj, {'name': 'Accept project', 'sort_order': 0}),
           op('create', 'task', t1, {'project_id': proj, 'title': 'Parent', 'notes': 'n', 'sort_order': 0}),
           op('create', 'task', t2, {'project_id': proj, 'parent_id': t1, 'title': 'Child', 'notes': '', 'sort_order': 0})]
    s, js, ms, nb = push(ta, a1, ops)
    ok = s == 200 and [r['status'] for r in js['results']] == ['applied'] * 3
    check('push project and two tasks', ok, f'{s} {ms:.0f}ms {nb}B')
    s2, js2, _, _ = push(ta, a1, ops)  # lost-response replay
    check('idempotent replay after a lost response', s2 == 200 and all(r.get('replayed') for r in js2['results']), f'{s2}')
    rep_ver = [r['applied_version'] for r in js['results']]
    check('replay returns the original result', [r['applied_version'] for r in js2['results']] == rep_ver)
    bad = [dict(ops[1], patch={'project_id': proj, 'title': 'Other', 'notes': '', 'sort_order': 0})]
    s, js3, _, _ = push(ta, a1, [bad[0]])
    check('operation_id reuse with a different body is rejected', s == 200 and js3['results'][0].get('error_code') == 'operation_id_reuse', f'{s}')

    # --- pull incremental
    s, js, ms, nb = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0, 'p_limit': 200})
    kinds = sorted(c['entity_type'] for c in js['changes']) if s == 200 else []
    check('pull from cursor 0 on device A2 returns the 3 entities', s == 200 and kinds == ['project', 'task', 'task'], f'{s} {kinds}')
    cur = js['next_cursor']
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': cur, 'p_limit': 200})
    check('incremental pull from the new cursor is empty', s == 200 and js['changes'] == [] and js['has_more'] is False, f'{s}')
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 10**15, 'p_limit': 10})
    check('forged future cursor is refused', s != 200 and 'invalid_cursor' in str(err_msg(js)), f'{s} {err_msg(js)}')

    # --- cross-user isolation
    s, js, _, _ = rpc(tb, 'nexora_sync_pull', {'p_device_id': b1, 'p_cursor': 0, 'p_limit': 200})
    check('B pulls nothing of A', s == 200 and js['changes'] == [] and js['conflicts'] == [], f'{s}')
    s, js, _, _ = rpc(tb, 'nexora_sync_pull', {'p_device_id': a1, 'p_cursor': 0, 'p_limit': 200})
    check("B cannot pull with A's device", s != 200, f'{s} {err_msg(js)}')
    s, js, _, _ = push(tb, b1, [op('update', 'task', t1, {'title': 'hijack'}, base=1)])
    check("B cannot update A's task (not_found)", s == 200 and js['results'][0].get('error_code') == 'not_found', f'{s} {js}')
    s, js, _, _ = push(tb, b1, [op('create', 'task', str(uuid.uuid4()), {'project_id': proj, 'title': 'plant', 'notes': '', 'sort_order': 0})])
    check("B cannot create a task in A's project", s == 200 and js['results'][0].get('status') == 'rejected', f'{s} {js}')
    s, js, _, _ = http('GET', '/rest/v1/tasks?select=id', tb)
    check('B direct SELECT on tasks sees nothing of A', s == 200 and js == [], f'{s} {len(js or [])}')
    s, js, _, _ = http('GET', '/rest/v1/sync_operations?select=user_id', tb)
    check('B direct SELECT on sync_operations sees only B rows', s in (200, 401, 403) and all(r['user_id'] == sub_of(tb) for r in (js or [])), f'{s} rows={len(js or [])}')
    s, js, _, _ = http('GET', '/rest/v1/tasks?select=id', ta)
    check('A direct SELECT still works (reads kept)', s == 200 and len(js) == 2, f'{s} {len(js or [])}')
    for sch in ('nexora_private',):
        s, js, _, _ = http('POST', '/rest/v1/rpc/push', ta, {'p_device_id': a1, 'p_ops': []}, {'Content-Profile': sch, 'Accept-Profile': sch})
        check('nexora_private schema is not exposed', s in (400, 404, 406), f'{s} {err_msg(js)}')

    # --- conflict: A2 edits with a stale base while A1 already changed the same field
    s, js, _, _ = push(ta, a1, [op('update', 'task', t1, {'title': 'Edited on A1'}, base=1)])
    check('A1 updates title (applied)', s == 200 and js['results'][0]['status'] == 'applied', f'{s} {js["results"][0].get("status")}')
    s, js, _, _ = push(ta, a2, [op('update', 'task', t1, {'title': 'Edited on A2'}, base=1)])
    r = js['results'][0] if s == 200 else {}
    check('stale-base edit on A2 becomes a conflict, nothing applied', r.get('status') == 'conflict', f'{s} {r.get("status")}')
    cid = r.get('conflict_id')
    s, js, _, _ = push(ta, a2, [op('update', 'task', t1, {'notes': 'more'}, base=2)])
    check('entity with an open conflict is blocked', s == 200 and js['results'][0].get('error_code') == 'blocked_by_conflict', f'{s}')
    s, js, _, _ = rpc(tb, 'nexora_resolve_conflict', {'p_device_id': b1, 'p_operation_id': str(uuid.uuid4()), 'p_conflict_id': cid, 'p_resolution': 'resolved_server'})
    check("B cannot resolve A's conflict", s == 200 and js.get('error_code') == 'not_found', f'{s} {js}')
    ropid = str(uuid.uuid4())
    body = {'p_device_id': a2, 'p_operation_id': ropid, 'p_conflict_id': cid, 'p_resolution': 'resolved_client'}
    s, js, _, _ = rpc(ta, 'nexora_resolve_conflict', body)
    check('A resolves the conflict (client wins)', s == 200 and js.get('status') == 'applied', f'{s} {js.get("status") if js else ""}')
    s, js, _, _ = rpc(ta, 'nexora_resolve_conflict', body)
    check('resolution replay is idempotent', s == 200 and js.get('replayed') is True, f'{s}')
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a1, 'p_cursor': 0, 'p_limit': 200})
    title = next((c['row']['title'] for c in js['changes'] if c['row']['id'] == t1), None)
    st = [c['status'] for c in js['conflicts']]
    check('pull shows the resolved title and the conflict as resolved', title == 'Edited on A2' and st == ['resolved_client'], f'{title} {st}')

    # --- atomic tree delete of the small tree
    s, js, _, _ = push(ta, a1, [op('delete', 'task', t1, base=3)])
    check('delete of a parent with a live child is a conflict (no cascade)', s == 200 and js['results'][0]['status'] == 'conflict', f'{s} {js["results"][0].get("kind") if s==200 else ""}')
    # --- device revocation
    s, js, _, _ = rpc(ta, 'nexora_revoke_device', {'p_device_id': a2, 'p_target_device_id': a1})
    check('A2 revokes A1', s == 200 and js.get('revoked') is True, f'{s}')
    s, js, _, _ = push(ta, a1, [op('create', 'project', str(uuid.uuid4()), {'name': 'after revoke', 'sort_order': 1})])
    check('revoked device cannot push', s != 200 and 'device_invalid' in str(err_msg(js)), f'{s} {err_msg(js)}')
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a1, 'p_cursor': 0})
    check('revoked device cannot pull', s != 200 and 'device_invalid' in str(err_msg(js)), f'{s}')
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0})
    check('the other device still works', s == 200, f'{s}')
    return dict(a2=a2, b1=b1, proj=proj, a1=a1)


def perf_phase(ta, a2):
    perf = {}
    big = str(uuid.uuid4())
    s, js, ms, nb = push(ta, a2, [op('create', 'project', big, {'name': 'Perf', 'sort_order': 0})])
    ids = []
    # 100-operation push (one batch)
    ops = []
    for i in range(100):
        tid = str(uuid.uuid4()); ids.append(tid)
        ops.append(op('create', 'task', tid, {'project_id': big, 'title': f'perf {i}', 'notes': 'x' * 200, 'sort_order': i}))
    s, js, ms, nb = push(ta, a2, ops)
    ok = s == 200 and all(r['status'] == 'applied' for r in js['results'])
    perf['push_100_ops'] = {'status': s, 'ms': round(ms), 'bytes': nb}
    check('push of 100 operations', ok, f'{s} {ms:.0f}ms {nb}B')
    # grow to 1,000 tasks
    for k in range(9):
        ops = []
        for i in range(100):
            tid = str(uuid.uuid4()); ids.append(tid)
            ops.append(op('create', 'task', tid, {'project_id': big, 'title': f'perf {k}-{i}', 'notes': '', 'sort_order': i}))
        s, js, _, _ = push(ta, a2, ops)
        assert s == 200, (s, js)
    check('1,000 tasks created', len(ids) == 1000, len(ids))
    # 500-row pull page
    s, js, ms, nb = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0, 'p_limit': 500})
    n = (len(js['changes']) + len(js['conflicts'])) if s == 200 else 0
    perf['pull_500_rows'] = {'status': s, 'ms': round(ms), 'bytes': nb, 'rows': n}
    check('pull page of 500 rows', s == 200 and n == 500, f'{s} {ms:.0f}ms {nb}B rows={n}')
    # tree delete with 1,000 descendants
    tree = [{'id': i, 'base_version': 1} for i in ids]
    s, js, ms, nb = push(ta, a2, [op('delete', 'project', big, {'tree': tree}, base=1)])
    r = js['results'][0] if s == 200 else {}
    perf['tree_delete_1000'] = {'status': s, 'ms': round(ms), 'bytes': nb, 'result': r.get('status'), 'tree_deleted': r.get('tree_deleted')}
    check('atomic tree delete of 1,000 descendants', r.get('status') == 'applied' and r.get('tree_deleted') == 1001, f'{s} {ms:.0f}ms {nb}B {r.get("status")} {r.get("tree_deleted")}')
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0, 'p_limit': 500})
    # ----- response size bound
    proj = str(uuid.uuid4())
    push(ta, a2, [op('create', 'project', proj, {'name': 'Big', 'sort_order': 1})])
    bigids = []
    for k in range(5):
        ops = []
        for i in range(4):
            tid = str(uuid.uuid4()); bigids.append(tid)
            ops.append(op('create', 'task', tid, {'project_id': proj, 'title': f'big {k}-{i}', 'notes': 'y' * 200000, 'sort_order': i}))
        s, js, _, nb = push(ta, a2, ops)
        assert s == 200, (s, str(js)[:200])
    ups = [op('update', 'task', t, {'title': 'renamed ' + t[:4]}, base=1) for t in bigids]
    s, js, ms, nb = push(ta, a2, ups)
    perf['oversized_response'] = {'status': s, 'ms': round(ms), 'bytes': nb, 'error': err_msg(js)}
    check('push whose response would exceed 2 MiB is refused (payload_too_large)', s != 200 and 'payload_too_large' in str(err_msg(js)), f'{s} {err_msg(js)} {ms:.0f}ms')
    s, js, _, _ = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0, 'p_limit': 500})
    first = [c for c in js['changes'] if c['row'].get('title', '').startswith('renamed')]
    check('the refused push recorded nothing', not first, len(first))
    ok = True; total = 0
    for chunk in (ups[:5], ups[5:10], ups[10:15], ups[15:]):
        s, js, ms, nb = push(ta, a2, chunk)
        ok = ok and s == 200 and all(r['status'] == 'applied' for r in js['results']); total += nb
    check('halved batches of the same operations succeed', ok, f'{total}B in 4 calls')
    s, js, ms, nb = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0, 'p_limit': 500})
    perf['pull_with_large_rows'] = {'status': s, 'ms': round(ms), 'bytes': nb}
    check('pull page bounded by bytes with large rows', s == 200 and nb <= 1048576 * 2, f'{s} {nb}B {ms:.0f}ms')
    return perf


def throttle_phase(tb, b1):
    """Aligned to the start of a one-minute bucket, concurrent calls, so a burst cannot straddle two buckets."""
    from concurrent.futures import ThreadPoolExecutor
    now = time.time()
    time.sleep(60 - (now % 60) + 1.0)          # just after a minute boundary
    def one(_):
        s, js, _, _ = rpc(tb, 'nexora_sync_pull', {'p_device_id': b1, 'p_cursor': 0, 'p_limit': 1})
        return s, err_msg(js), (js or {}).get('code')
    t0 = time.time()
    with ThreadPoolExecutor(12) as ex:
        res = list(ex.map(one, range(140)))
    elapsed = time.time() - t0
    ok_n = sum(1 for r in res if r[0] == 200)
    limited = [r for r in res if r[0] != 200]
    check('burst of pulls is answered with rate_limited (NX007)', limited and all(r[1] == 'rate_limited' for r in limited) and ok_n <= 120 + 12,
          f'{ok_n} ok, {len(limited)} limited, first={limited[0] if limited else None}, {elapsed:.1f}s')
    time.sleep(61)
    s, js, _, _ = rpc(tb, 'nexora_sync_pull', {'p_device_id': b1, 'p_cursor': 0, 'p_limit': 1})
    check('account recovers in the next window', s == 200, f'{s}')
    return {'ok_before_limit': ok_n, 'limited': len(limited)}


def s9_phase(ta, tb, a2):
    pid = str(uuid.uuid4())
    for m, path, body in (('POST', '/rest/v1/projects', {'id': pid, 'owner_id': 'x', 'name': 'direct'}),
                          ('PATCH', '/rest/v1/projects?name=eq.Accept%20project', {'name': 'hijack'}),
                          ('DELETE', '/rest/v1/projects?name=eq.Accept%20project', None),
                          ('POST', '/rest/v1/tasks', {'id': pid, 'title': 'direct'}),
                          ('PATCH', '/rest/v1/tasks?title=eq.Child', {'title': 'hijack'}),
                          ('DELETE', '/rest/v1/tasks?title=eq.Child', None)):
        s, js, _, _ = http(m, path, ta, body, {'Prefer': 'return=representation'})
        check(f'S9: direct {m} {path.split("?")[0]} refused', s in (401, 403), f'{s} {err_msg(js)}')
    s, js, _, _ = http('GET', '/rest/v1/projects?select=name', ta)
    check('S9: SELECT on projects still works', s == 200 and len(js) >= 1, f'{s}')
    s, js, _, _ = http('GET', '/rest/v1/profiles?select=id', ta)
    check('S9: profiles SELECT still works', s == 200, f'{s} {len(js or [])}')
    s, js, _, _ = http('PATCH', '/rest/v1/profiles?id=eq.00000000-0000-0000-0000-000000000000', ta, {'display_name': 'x'}, {'Prefer': 'return=representation'})
    check('S9: profiles UPDATE keeps its intended permission (not a 403)', s != 403 or 'permission denied' not in str(err_msg(js)), f'{s} {err_msg(js)}')
    ops = [op('create', 'task', str(uuid.uuid4()), {'project_id': str(uuid.uuid4()), 'title': 'rpc still works', 'notes': '', 'sort_order': 0})]
    s, js, _, _ = push(ta, a2, ops)
    check('S9: RPC push path still answers (project unknown -> rejected, not denied)', s == 200 and js['results'][0].get('status') == 'rejected', f'{s}')
    pj = str(uuid.uuid4())
    s, js, _, _ = push(ta, a2, [op('create', 'project', pj, {'name': 'post-S9 via RPC', 'sort_order': 9})])
    check('S9: creating a project through the RPC still works', s == 200 and js['results'][0]['status'] == 'applied', f'{s}')


if __name__ == '__main__':
    phase = sys.argv[1] if len(sys.argv) > 1 else 'all'
    ta, ja = login(os.environ['NEXORA_USER_A'], os.environ['NEXORA_PASS_A'])
    tb, jb = login(os.environ['NEXORA_USER_B'], os.environ['NEXORA_PASS_B'])
    claims = {'expires_in': ja.get('expires_in'), 'has_refresh_token': bool(ja.get('refresh_token'))}
    check('sign-in returns a JWT and a refresh token', claims['has_refresh_token'], f"expires_in={claims['expires_in']}")
    s, js, _, _ = http('GET', '/auth/v1/user', ta)
    check('JWT validates at /auth/v1/user and is not anonymous', s == 200 and not js.get('is_anonymous'), f'{s}')
    report = {'auth': claims}
    ctx = {}
    if phase in ('main', 'all'):
        ctx = main_phase(ta, tb, None, None)
        report['perf'] = perf_phase(ta, ctx['a2'])
        report['throttle'] = throttle_phase(tb, ctx['b1'])
    if phase == 'recheck':
        a2 = str(uuid.uuid4()); b1 = str(uuid.uuid4())
        rpc(ta, 'nexora_register_device', {'p_device_id': a2, 'p_label': 'accept-recheck'})
        rpc(tb, 'nexora_register_device', {'p_device_id': b1, 'p_label': 'accept-recheck'})
        s, js, _, _ = http('GET', '/rest/v1/sync_operations?select=user_id', tb)
        check('B direct SELECT on sync_operations sees only B rows', s == 200 and all(r['user_id'] == sub_of(tb) for r in js), f'{s} rows={len(js)}')
        s, js, ms, nb = rpc(ta, 'nexora_sync_pull', {'p_device_id': a2, 'p_cursor': 0, 'p_limit': 500})
        n = len(js['changes']) + len(js['conflicts']) if s == 200 else 0
        check('pull page of 500 items', s == 200 and n == 500 and js['has_more'], f'{s} {ms:.0f}ms {nb}B items={n} has_more={js.get("has_more") if js else None}')
        report['throttle'] = throttle_phase(tb, b1)
    if phase in ('s9',):
        a2 = str(uuid.uuid4())
        rpc(ta, 'nexora_register_device', {'p_device_id': a2, 'p_label': 'accept-s9'})
        s9_phase(ta, tb, a2)
    report['results'] = RESULTS
    failed = [r for r in RESULTS if not r['ok']]
    report['summary'] = {'total': len(RESULTS), 'failed': len(failed)}
    print('REPORT ' + json.dumps({k: v for k, v in report.items() if k != 'results'}))
    sys.exit(1 if failed else 0)
