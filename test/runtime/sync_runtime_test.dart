import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_panel.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/runtime/runtime_config.dart';
import 'package:nexora/runtime/sync_runtime.dart';

import '../support/fake_auth.dart';
import '../support/fake_sync_server.dart';
import '../support/task_fixtures.dart';
import '../support/token_gate_transport.dart';

final class _FixedClock implements Clock {
  @override
  CalendarDate today() => const CalendarDate(2026, 11, 12);
}

void main() {
  late Directory dir;
  late FakeAuthApi api;
  late InMemorySecureStore store;
  var clock = DateTime.utc(2026, 11, 12, 12);
  var factoryCalls = 0;
  late Map<String, FakeSyncServer> servers;

  RuntimeConfig config() => RuntimeConfig.validate(
    'http://127.0.0.1:1',
    fakeJwt(sub: userA, expiresAt: DateTime.utc(2035), role: 'anon'),
  )!;

  SyncRuntime build({RuntimeConfig? cfg, bool noConfig = false}) {
    final sessions = SessionManager(api: api, store: store, now: () => clock);
    return SyncRuntime(
      sessions: sessions,
      paths: AccountPaths(dir),
      localDatabasePath: '${dir.path}${Platform.pathSeparator}nexora.db',
      config: noConfig ? null : (cfg ?? config()),
      ids: RandomIdGenerator(),
      clock: _FixedClock(),
      schedulerInterval: const Duration(hours: 1),
      autoSyncOnSignIn: false,
      sleep: (d) async {},
      transportFactory: (c, token) {
        factoryCalls++;
        final user = sessionsUser(sessions);
        return TokenGate(
          servers.putIfAbsent(user, FakeSyncServer.new),
          token,
        );
      },
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexora-rt-');
    clock = DateTime.utc(2026, 11, 12, 12);
    api = FakeAuthApi(() => clock);
    store = InMemorySecureStore();
    factoryCalls = 0;
    servers = {};
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a database handle may still be closing on Windows
    }
  });

  test(
    'signed out: the local workspace, no engine, no transport, no traffic',
    () async {
      final runtime = build();
      final active = await runtime.start();
      addTearDown(runtime.dispose);

      expect(active.userId, isNull);
      expect(active.engine, isNull);
      expect(active.scheduler, isNull);
      expect(factoryCalls, 0);
      expect((await runtime.syncNow()).phase, SyncPhase.authRequired);
      expect(api.signIns + api.refreshes, 0);
      expect(
        File('${dir.path}${Platform.pathSeparator}nexora.db').existsSync(),
        isTrue,
      );
    },
  );

  test('without project settings nothing is ever built', () async {
    final runtime = build(noConfig: true);
    await runtime.start();
    addTearDown(runtime.dispose);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.success);
    expect(runtime.active.engine, isNull);
    expect(factoryCalls, 0);
    expect(runtime.syncPanel().initial.phase, isNot(SyncPhase.idle));
  });

  test(
    'sign-in opens the account database, builds the engine and synchronizes',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      await runtime.signIn('a@example.test', 'pw');
      final active = runtime.active;
      expect(active.userId, userA);
      expect(
        active.db.raw
            .select('PRAGMA database_list')
            .first['file']
            .toString()
            .contains('accounts'),
        isTrue,
      );

      await active.repository.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await active.repository.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'Synced'),
      );
      final status = await runtime.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(servers[userA]!.rows.keys, containsAll(['project:p1', 'task:t1']));
      expect(runtime.active.scheduler!.running, isTrue);
    },
  );

  test(
    'sign-out returns to the local workspace and stops everything',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      await runtime.signIn('a@example.test', 'pw');
      await runtime.signOut();

      expect(runtime.active.userId, isNull);
      expect(runtime.active.engine, isNull);
      final calls = factoryCalls;
      await runtime.syncNow();
      expect(factoryCalls, calls);
      expect(await store.read('session'), isNull);
    },
  );

  test(
    'account switching: each account has its own file and data never crosses',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);

      await runtime.signIn('a@example.test', 'pw');
      await runtime.active.repository.saveProject(
        const Project(id: 'pa', name: 'A only', position: 0),
      );
      await runtime.syncNow();
      await runtime.signOut();

      await runtime.signIn('b@example.test', 'pw');
      expect(runtime.active.userId, userB);
      expect(await runtime.active.repository.loadProjects(), isEmpty);
      await runtime.active.repository.saveProject(
        const Project(id: 'pb', name: 'B only', position: 0),
      );
      await runtime.syncNow();

      expect(servers[userA]!.rows.keys, contains('project:pa'));
      expect(servers[userA]!.rows.keys, isNot(contains('project:pb')));
      expect(servers[userB]!.rows.keys, contains('project:pb'));
      expect(servers[userB]!.rows.keys, isNot(contains('project:pa')));

      await runtime.signOut();
      await runtime.signIn('a@example.test', 'pw');
      expect(
        (await runtime.active.repository.loadProjects()).map((p) => p.id),
        ['pa'],
      );
    },
  );

  test(
    'an expired session keeps the account database usable and sends nothing',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      await runtime.signIn('a@example.test', 'pw');
      await runtime.active.repository.saveProject(
        const Project(id: 'p1', name: 'Offline work', position: 0),
      );
      clock = clock.add(const Duration(hours: 3));
      api.refreshFailures.add(const AuthSessionRevoked('session_not_found'));

      final status = await runtime.syncNow();

      expect(status.phase, SyncPhase.authRequired);
      expect(runtime.active.userId, userA);
      expect(
        (await runtime.active.repository.loadProjects()).single.name,
        'Offline work',
      );
      expect(servers[userA]!.rows, isEmpty);
      final view = runtime.accountPanel().initial;
      expect(view.phase, AccountPhase.reauthRequired);
    },
  );

  test(
    'restart restores the account offline without any network call',
    () async {
      final first = build();
      await first.start();
      await first.signIn('a@example.test', 'pw');
      await first.active.repository.saveProject(
        const Project(id: 'p1', name: 'Mine', position: 0),
      );
      await first.dispose();
      final signIns = api.signIns;

      final second = build();
      final active = await second.start();
      addTearDown(second.dispose);

      expect(active.userId, userA);
      expect((await active.repository.loadProjects()).single.name, 'Mine');
      expect(api.signIns, signIns);
      expect(api.refreshes, 0);
    },
  );

  test('a bad sign-in maps to an outcome the dialog can show', () async {
    final runtime = build();
    await runtime.start();
    addTearDown(runtime.dispose);
    api.signInFailures.add(const AuthInvalidCredentials());
    expect(await runtime.signIn('a', 'x'), SignInOutcome.invalidCredentials);
    api.signInFailures.add(const AuthNetworkFailure('connection'));
    expect(await runtime.signIn('a', 'x'), SignInOutcome.offline);
    api.anonymousNext = true;
    expect(await runtime.signIn('a', 'x'), SignInOutcome.anonymousRejected);
    expect(runtime.active.userId, isNull);
  });

  test('a transport that fails keeps pending work (network loss)', () async {
    final runtime = SyncRuntime(
      sessions: SessionManager(api: api, store: store, now: () => clock),
      paths: AccountPaths(dir),
      localDatabasePath: '${dir.path}${Platform.pathSeparator}nexora.db',
      config: config(),
      ids: RandomIdGenerator(),
      clock: _FixedClock(),
      schedulerInterval: const Duration(hours: 1),
      autoSyncOnSignIn: false,
      sleep: (d) async {},
      transportFactory: (c, t) => FaultyTransport(FakeSyncServer())
        ..pushFaults.addAll(
          List.filled(10, const PushFault(SyncNetworkFailure('offline'))),
        ),
    );
    await runtime.start();
    addTearDown(runtime.dispose);
    await runtime.signIn('a@example.test', 'pw');
    await runtime.active.repository.saveProject(
      const Project(id: 'p1', name: 'Kept', position: 0),
    );

    final status = await runtime.syncNow();

    expect(status.phase, SyncPhase.retrying);
    expect(status.pending, greaterThan(0));
  });
}

String sessionsUser(SessionManager m) => m.userId ?? 'none';
