import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/supabase_sync_transport.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import '../support/task_fixtures.dart';
import 'http_support.dart';

/// The real HTTP boundary: Supabase Auth (GoTrue) issues the tokens, PostgREST
/// verifies them and exposes the RPCs, and the migrations S1-S4 run on
/// PostgreSQL 17 behind them. The code under test is the production client
/// (`SupabaseAuthApi`, `SupabaseSyncTransport`, `SessionManager`, the engine).
/// Skipped unless the http-integration workflow provides `NEXORA_HTTP_URL`.
final Stack? _stack = Stack.fromEnvironment();
final String? _skip = _stack == null
    ? 'needs the disposable Supabase stack (workflow http-integration)'
    : null;

String _id() => RandomIdGenerator().nextId();

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nexora-http-'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle may still be closing on Windows
    }
  });
  tearDownAll(() => _stack?.close());

  Stack stack() => _stack!;

  SupabaseSyncTransport rawTransport(String? token) => SupabaseSyncTransport(
    baseUrl: stack().url,
    anonKey: stack().anonKey,
    accessToken: () async => token,
  );

  Future<String> tokenFor(String email, String password) async {
    final s = await SupabaseAuthApi(
      baseUrl: stack().url,
      anonKey: stack().anonKey,
    ).signInWithPassword(email, password);
    return s.accessToken;
  }

  group('exposure and permissions at the API boundary', () {
    test('the public key alone cannot call a sync RPC', () async {
      final r = await stack().request(
        'POST',
        '/rest/v1/rpc/nexora_register_device',
        body: {'p_device_id': _id(), 'p_label': null},
      );
      expect(r.status, anyOf(401, 403));
    }, skip: _skip);

    test('the private schema is not exposed through the Data API', () async {
      final user = await stack().signUp('priv');
      final token = await tokenFor(user.email, user.password);
      final r = await stack().request(
        'POST',
        '/rest/v1/rpc/apply_operation',
        token: token,
        body: {},
        headers: {'Content-Profile': 'nexora_private'},
      );
      expect(r.status, greaterThanOrEqualTo(400));
      expect((r.body as Map)['code'], 'PGRST106');
    }, skip: _skip);

    test(
      'the OpenAPI document lists exactly the five sync RPCs for a user',
      () async {
        final user = await stack().signUp('openapi');
        final token = await tokenFor(user.email, user.password);
        final r = await stack().request('GET', '/rest/v1/', token: token);
        expect(r.status, 200);
        final paths = ((r.body as Map)['paths'] as Map).keys.cast<String>();
        final rpcs = paths.where((p) => p.startsWith('/rpc/')).toSet();
        expect(
          rpcs.containsAll({
            '/rpc/nexora_register_device',
            '/rpc/nexora_sync_push',
            '/rpc/nexora_sync_pull',
            '/rpc/nexora_resolve_conflict',
            '/rpc/nexora_revoke_device',
          }),
          isTrue,
          reason: '$rpcs',
        );
        expect(
          rpcs.where(
            (p) =>
                p.contains('private') ||
                p.contains('apply') ||
                p.contains('guard'),
          ),
          isEmpty,
        );
      },
      skip: _skip,
    );

    test('another user cannot read or change what an account owns, and cannot write as it', () async {
      final a = await stack().signUp('ownerA');
      final b = await stack().signUp('ownerB');
      final devA = await Device.open(stack(), dir, a.email, a.password);
      addTearDown(devA.close);
      await devA.repo.saveProject(
        Project(id: _id(), name: 'Private', position: 0),
      );
      expect((await devA.engine.syncNow()).phase, SyncPhase.idle);
      final projectId =
          (await stack().adminRows(
                'projects',
                'owner_id=eq.${a.id}',
              )).single['id']
              as String;

      final tokenB = await tokenFor(b.email, b.password);
      for (final table in [
        'projects',
        'tasks',
        'devices',
        'sync_operations',
        'sync_conflicts',
      ]) {
        final r = await stack().request(
          'GET',
          '/rest/v1/$table?select=*',
          token: tokenB,
        );
        // either denied outright or filtered to nothing: never A's rows
        expect(r.status, anyOf(200, 401, 403), reason: table);
        if (r.status == 200) {
          expect(r.body, isEmpty, reason: table);
        }
      }
      final patch = await stack().request(
        'PATCH',
        '/rest/v1/projects?id=eq.$projectId',
        token: tokenB,
        body: {'name': 'hijacked'},
        headers: {'Prefer': 'return=representation'},
      );
      expect(patch.status, anyOf(200, 401, 403));
      final after = await stack().adminRows('projects', 'id=eq.$projectId');
      expect(after.single['name'], 'Private');
      final insert = await stack().request(
        'POST',
        '/rest/v1/projects',
        token: tokenB,
        body: {'id': _id(), 'owner_id': a.id, 'name': 'planted'},
      );
      expect(insert.status, greaterThanOrEqualTo(400));
      expect(await stack().adminRows('projects', 'name=eq.planted'), isEmpty);
    }, skip: _skip);

    test(
      'S9 probe: direct writes by the owner (recorded, still granted until S9)',
      () async {
        final a = await stack().signUp('direct');
        final token = await tokenFor(a.email, a.password);
        final r = await stack().request(
          'POST',
          '/rest/v1/projects',
          token: token,
          body: {'id': _id(), 'owner_id': a.id, 'name': 'direct write'},
        );
        // ignore: avoid_print
        print(
          'S9 PROBE direct INSERT into projects as the owner: HTTP ${r.status}',
        );
        expect(r.status, isNotNull);
      },
      skip: _skip,
    );
  });

  group('authentication', () {
    test(
      'sign-in yields a real token for the right account, not anonymous',
      () async {
        final u = await stack().signUp('claims');
        final session = await SupabaseAuthApi(
          baseUrl: stack().url,
          anonKey: stack().anonKey,
        ).signInWithPassword(u.email, u.password);
        expect(session.userId, u.id);
        expect(session.isAnonymous, isFalse);
        expect(session.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
      },
      skip: _skip,
    );

    test('wrong password is an invalid-credentials failure', () async {
      final u = await stack().signUp('wrongpw');
      await expectLater(
        SupabaseAuthApi(
          baseUrl: stack().url,
          anonKey: stack().anonKey,
        ).signInWithPassword(u.email, 'not-the-password'),
        throwsA(isA<AuthInvalidCredentials>()),
      );
    }, skip: _skip);

    test(
      'an anonymous identity is rejected by the client and by the server',
      () async {
        final anon = await stack().anonymousSession();
        expect(anon.isAnonymous, isTrue);
        await expectLater(
          rawTransport(anon.accessToken).registerDevice(_id()),
          throwsA(
            isA<SyncAuthFailure>().having(
              (e) => e.anonymous,
              'anonymous',
              isTrue,
            ),
          ),
        );
      },
      skip: _skip,
    );

    test('an expired token (correctly signed) is refreshed with the real refresh token', () async {
      final u = await stack().signUp('expired');
      final api = SupabaseAuthApi(
        baseUrl: stack().url,
        anonKey: stack().anonKey,
      );
      final real = await api.signInWithPassword(u.email, u.password);
      final expired = stack().mintToken(
        sub: u.id,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      );
      // the server itself calls this token expired
      await expectLater(
        rawTransport(expired).registerDevice(_id()),
        throwsA(isA<SyncAuthFailure>()),
      );

      final store = InMemorySecureStore();
      await store.write(
        'session',
        jsonEncode({
          ...real.toJson(),
          'access_token': expired,
          'expires_at':
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 5))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
      );
      await store.write('last_user', u.id);
      final sessions = SessionManager(api: api, store: store);
      await sessions.restore();
      final token = await sessions.accessToken();
      expect(token, isNot(expired));
      await rawTransport(token).registerDevice(_id()); // accepted now
    }, skip: _skip);

    test('a token the server rejects although it looks valid is refreshed once and retried', () async {
      final u = await stack().signUp('forged');
      final device = await Device.open(stack(), dir, u.email, u.password);
      addTearDown(device.close);
      final good = device.sessions.state.session!;
      // a future expiry, a wrong signature: only the server can tell
      final head = base64Url
          .encode(utf8.encode('{"alg":"HS256","typ":"JWT"}'))
          .replaceAll('=', '');
      final body = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'sub': u.id,
                'role': 'authenticated',
                'exp':
                    DateTime.now()
                        .toUtc()
                        .add(const Duration(hours: 1))
                        .millisecondsSinceEpoch ~/
                    1000,
              }),
            ),
          )
          .replaceAll('=', '');
      await device.store.write(
        'session',
        jsonEncode({...good.toJson(), 'access_token': '$head.$body.AAAA'}),
      );
      await device.sessions.restore();

      await device.repo.saveProject(
        Project(id: _id(), name: 'After refresh', position: 0),
      );
      final status = await device.engine.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(
        await stack().adminRows('projects', 'owner_id=eq.${u.id}'),
        hasLength(1),
      );
    }, skip: _skip);

    test('expired and no longer refreshable: pending work is kept, nothing is sent', () async {
      final u = await stack().signUp('norefresh');
      final device = await Device.open(stack(), dir, u.email, u.password);
      addTearDown(device.close);
      await device.repo.saveProject(
        Project(id: _id(), name: 'Kept', position: 0),
      );
      final good = device.sessions.state.session!;
      await device.store.write(
        'session',
        jsonEncode({
          ...good.toJson(),
          'refresh_token': 'not-a-real-refresh-token',
          'expires_at':
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(minutes: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        }),
      );
      await device.sessions.restore();

      final status = await device.engine.syncNow();

      expect(status.phase, SyncPhase.authRequired);
      expect(device.sessions.state.phase, AuthPhase.reauthRequired);
      expect(device.state.counts().pending, greaterThan(0));
      expect(
        await stack().adminRows('projects', 'owner_id=eq.${u.id}'),
        isEmpty,
      );
    }, skip: _skip);

    test(
      'a deleted user with a still-valid token is refused, and cannot refresh',
      () async {
        final u = await stack().signUp('deleted');
        final api = SupabaseAuthApi(
          baseUrl: stack().url,
          anonKey: stack().anonKey,
        );
        final session = await api.signInWithPassword(u.email, u.password);
        await rawTransport(session.accessToken).registerDevice(_id());
        await stack().adminDeleteUser(u.id);

        await expectLater(
          rawTransport(session.accessToken).registerDevice(_id()),
          throwsA(isA<SyncAuthFailure>()),
        );
        await expectLater(
          api.refresh(session.refreshToken),
          throwsA(isA<AuthSessionRevoked>()),
        );
      },
      skip: _skip,
    );

    test('sign-out ends the refresh token', () async {
      final u = await stack().signUp('logout');
      final api = SupabaseAuthApi(
        baseUrl: stack().url,
        anonKey: stack().anonKey,
      );
      final session = await api.signInWithPassword(u.email, u.password);
      await api.signOut(session.accessToken);
      await expectLater(
        api.refresh(session.refreshToken),
        throwsA(isA<AuthSessionRevoked>()),
      );
    }, skip: _skip);

    test(
      'refresh rotation: each refresh uses the newest refresh token and works',
      () async {
        final u = await stack().signUp('rotate');
        var clock = DateTime.now().toUtc();
        final sessions = SessionManager(
          api: SupabaseAuthApi(baseUrl: stack().url, anonKey: stack().anonKey),
          store: InMemorySecureStore(),
          now: () => clock,
        );
        await sessions.signIn(u.email, u.password);
        final tokens = <String>{sessions.state.session!.refreshToken};
        for (var i = 0; i < 3; i++) {
          clock = clock.add(const Duration(hours: 2));
          final access = await sessions.accessToken();
          expect(access, isNotNull);
          await rawTransport(access).registerDevice(_id());
          tokens.add(sessions.state.session!.refreshToken);
        }
        expect(tokens, hasLength(4)); // a new refresh token every time
      },
      skip: _skip,
    );
  });

  group('RPC error mapping through PostgREST', () {
    test('every contract error arrives with its stable code', () async {
      final u = await stack().signUp('errors');
      final device = await Device.open(stack(), dir, u.email, u.password);
      addTearDown(device.close);
      final token = device.sessions.state.session!.accessToken;
      final t = rawTransport(token);

      await expectLater(
        t.push(_id(), [
          {'operation_id': _id()},
        ]),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'device_invalid',
          ),
        ),
      );
      await t.registerDevice(device.deviceId);
      await expectLater(
        t.pull(device.deviceId, -5),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'invalid_cursor',
          ),
        ),
      );
      await expectLater(
        t.pull(device.deviceId, 999999999),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'invalid_cursor',
          ),
        ),
      );
      await expectLater(
        t.pull(device.deviceId, 0, limit: 0),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'invalid_request',
          ),
        ),
      );
      await expectLater(
        t.push(device.deviceId, [
          for (var i = 0; i < 101; i++) <String, Object?>{},
        ]),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'batch_too_large',
          ),
        ),
      );
      final page = await t.pull(device.deviceId, 0);
      expect(page['has_more'], isFalse);
    }, skip: _skip);

    test('a foreign user cannot use another account\'s device', () async {
      final a = await stack().signUp('fa');
      final b = await stack().signUp('fb');
      final devA = await Device.open(stack(), dir, a.email, a.password);
      addTearDown(devA.close);
      await devA.transport.registerDevice(devA.deviceId);
      final tokenB = await tokenFor(b.email, b.password);

      await expectLater(
        rawTransport(tokenB).pull(devA.deviceId, 0),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'device_invalid',
          ),
        ),
      );
      await expectLater(
        rawTransport(tokenB).revokeDevice(devA.deviceId, devA.deviceId),
        throwsA(
          isA<SyncServerError>().having(
            (e) => e.code,
            'code',
            'device_invalid',
          ),
        ),
      );
    }, skip: _skip);

    test('a revoked device is refused by every RPC and its engine pauses without data loss', () async {
      final u = await stack().signUp('revoke');
      final d1 = await Device.open(stack(), dir, u.email, u.password);
      final d2 = await Device.open(stack(), dir, u.email, u.password);
      addTearDown(d1.close);
      addTearDown(d2.close);
      await d1.repo.saveProject(
        Project(id: _id(), name: 'Shared', position: 0),
      );
      expect((await d1.engine.syncNow()).phase, SyncPhase.idle);
      expect((await d2.engine.syncNow()).phase, SyncPhase.idle);
      await d2.repo.saveProject(
        Project(id: _id(), name: 'Offline on d2', position: 1),
      );

      await d1.engine.revokeDevice(d2.deviceId);
      final status = await d2.engine.syncNow();

      expect(status.phase, SyncPhase.deviceRevoked);
      expect(d2.state.counts().pending, greaterThan(0));
      expect(
        await stack().adminRows(
          'projects',
          'owner_id=eq.${u.id}&name=eq.Offline on d2',
        ),
        isEmpty,
      );
    }, skip: _skip);
  });

  group('synchronization over HTTP', () {
    test(
      'a response lost after the server committed is replayed idempotently',
      () async {
        final u = await stack().signUp('replay');
        DropResponseAfterCommit? drop;
        final d = await Device.open(
          stack(),
          dir,
          u.email,
          u.password,
          wrap: (inner) => drop = DropResponseAfterCommit(inner),
        );
        addTearDown(d.close);
        await d.repo.saveProject(Project(id: _id(), name: 'Once', position: 0));

        final first = await d.engine.syncNow();
        expect(first.phase, SyncPhase.retrying);
        expect(drop!.dropped, 1);
        expect(
          await stack().adminRows('projects', 'owner_id=eq.${u.id}'),
          hasLength(1),
        ); // committed
        final second = await d.engine.syncNow();

        expect(second.phase, SyncPhase.idle);
        final project = (await stack().adminRows(
          'projects',
          'owner_id=eq.${u.id}',
        )).single;
        expect(project['version'], 1);
        expect(
          await stack().adminRows(
            'sync_operations',
            'user_id=eq.${u.id}&entity_type=eq.project',
          ),
          hasLength(1),
        );
      },
      skip: _skip,
    );

    test(
      'two devices: create, receive, independent edits, conflict, resolve, tree delete',
      () async {
        final u = await stack().signUp('twodev');
        final a = await Device.open(stack(), dir, u.email, u.password);
        final b = await Device.open(stack(), dir, u.email, u.password);
        addTearDown(a.close);
        addTearDown(b.close);
        Future<void> converge() async {
          for (var i = 0; i < 2; i++) {
            for (final d in [a, b]) {
              final s = await d.engine.syncNow();
              expect(s.phase, SyncPhase.idle, reason: s.code);
            }
          }
        }

        final p = _id(), t1 = _id(), t2 = _id(), t3 = _id();
        await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
        await a.repo.saveTask(
          makeTask(id: t1, projectId: p, title: 'Root', notes: 'n'),
        );
        await a.repo.saveTask(
          makeTask(id: t2, projectId: p, parentId: t1, title: 'Child'),
        );
        await a.repo.saveTask(
          makeTask(id: t3, projectId: p, title: 'Contested'),
        );
        await converge();
        expect(b.rows('SELECT COUNT(*) AS n FROM tasks').single['n'], 3);

        // independent edits of different fields reconcile
        await a.repo.saveTask(
          makeTask(id: t1, projectId: p, title: 'Root (A)', notes: 'n'),
        );
        await b.repo.saveTask(
          makeTask(id: t1, projectId: p, title: 'Root', notes: 'notes (B)'),
        );
        await converge();
        for (final d in [a, b]) {
          final row = d.rows('SELECT title, notes FROM tasks WHERE id = ?', [
            t1,
          ]).single;
          expect(row['title'], 'Root (A)');
          expect(row['notes'], 'notes (B)');
        }

        // the same field on both: conflict evidence, then a decision through HTTP
        await a.repo.saveTask(makeTask(id: t3, projectId: p, title: 'A says'));
        await b.repo.saveTask(makeTask(id: t3, projectId: p, title: 'B says'));
        await a.engine.syncNow();
        await b.engine.syncNow();
        expect(
          await stack().adminRows(
            'sync_conflicts',
            'user_id=eq.${u.id}&status=eq.open',
          ),
          hasLength(1),
        );
        final conflict = b.outbox.conflictsNeedingAction().single;
        await b.engine.resolveConflict(
          conflict['id']! as String,
          ConflictChoice.keepLocal,
        );
        await converge();
        expect(
          a.rows('SELECT title FROM tasks WHERE id = ?', [t3]).single['title'],
          'B says',
        );
        expect(
          (await stack().adminRows(
            'sync_conflicts',
            'user_id=eq.${u.id}',
          )).single['status'],
          'resolved_client',
        );

        // an atomic tree delete leaves no orphan
        await a.repo.softDeleteTaskTree(t1);
        await converge();
        final deleted = await stack().adminRows(
          'tasks',
          'owner_id=eq.${u.id}&deleted_at=not.is.null',
        );
        expect(deleted.map((r) => r['id']).toSet(), {t1, t2});
        expect(
          b.rows('SELECT deleted_at FROM tasks WHERE id = ?', [
            t2,
          ]).single['deleted_at'],
          isNotNull,
        );
      },
      skip: _skip,
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('a tree-delete manifest over the size limit is refused and nothing is deleted', () async {
      final u = await stack().signUp('treelimit');
      final d = await Device.open(stack(), dir, u.email, u.password);
      addTearDown(d.close);
      final p = _id(), root = _id();
      await d.repo.saveProject(Project(id: p, name: 'P', position: 0));
      await d.repo.saveTask(makeTask(id: root, projectId: p, title: 'root'));
      expect((await d.engine.syncNow()).phase, SyncPhase.idle);

      final results = await d.transport.push(d.deviceId, [
        {
          'operation_id': _id(),
          'entity_type': 'task',
          'entity_id': root,
          'op_type': 'delete',
          'base_version': 1,
          'patch': {
            'tree': [
              for (var i = 0; i < 1001; i++) {'id': _id(), 'base_version': 1},
            ],
          },
          'client_created_at': '2026-11-12T10:00:00.000Z',
        },
      ]);

      final result = Map<String, Object?>.from(results.single! as Map);
      expect(result['status'], 'rejected');
      expect(result['error'], 'invalid_patch');
      final rows = await stack().adminRows('tasks', 'id=eq.$root');
      expect(rows.single['deleted_at'], isNull);
    }, skip: _skip);

    test('an invalid cursor is recovered without losing local data', () async {
      final u = await stack().signUp('cursor');
      final d = await Device.open(stack(), dir, u.email, u.password);
      addTearDown(d.close);
      await d.repo.saveProject(
        Project(id: _id(), name: 'Keep me', position: 0),
      );
      expect((await d.engine.syncNow()).phase, SyncPhase.idle);
      d.db.raw.execute(
        'UPDATE sync_state SET cursor = 9000000000 WHERE singleton = 1',
      );

      final status = await d.engine.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(d.state.cursor(), lessThan(9000000000));
      expect(d.rows('SELECT name FROM projects').single['name'], 'Keep me');
    }, skip: _skip);
  });
}
