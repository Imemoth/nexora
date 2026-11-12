import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/runtime/runtime_config.dart';
import 'package:nexora/runtime/sync_runtime.dart';

import '../support/fake_auth.dart';
import '../support/fake_sync_server.dart';
import '../support/task_fixtures.dart';
import '../support/token_gate_transport.dart';
import '../support/v1_database.dart';

/// S8: acceptance scenarios at application level, with real SQLite files, the real
/// session manager, the real runtime and the real engine. On Windows the session is
/// kept with the real Windows protection (DPAPI); elsewhere an in-memory store
/// stands in (the scenario logic is identical). The server is the in-memory fake
/// with the S2-S4 semantics; the real server is exercised by the e2e-sync and
/// http-integration workflows.
final class _Crash implements Exception {
  const _Crash();
}

final class _FixedClock implements Clock {
  @override
  CalendarDate today() => const CalendarDate(2026, 11, 12);
}

String _id() => RandomIdGenerator().nextId();

void main() {
  late Directory root;
  var now = DateTime.utc(2026, 11, 12, 12);
  late Map<String, FakeSyncServer> servers;
  var folders = 0;

  RuntimeConfig config() => RuntimeConfig.validate(
    'http://127.0.0.1:1',
    fakeJwt(sub: userA, expiresAt: DateTime.utc(2035), role: 'anon'),
  )!;

  SecureStore storeIn(Directory dir) => Platform.isWindows
      ? DpapiSecureStore(
          Directory('${dir.path}${Platform.pathSeparator}session'),
        )
      : InMemorySecureStore();

  /// One installation: its own folder, session store and runtime.
  ({SyncRuntime runtime, Directory dir, FakeAuthApi api}) install({
    Directory? dir,
    SecureStore? store,
    FakeAuthApi? api,
    SyncTransport Function(SyncTransport inner)? wrap,
    SyncHook? hook,
  }) {
    final folder =
        dir ??
              Directory(
                '${root.path}${Platform.pathSeparator}install${folders++}',
              )
          ..createSync(recursive: true);
    final auth = api ?? FakeAuthApi(() => now);
    final sessions = SessionManager(
      api: auth,
      store: store ?? storeIn(folder),
      now: () => now,
    );
    final runtime = SyncRuntime(
      sessions: sessions,
      paths: AccountPaths(folder),
      localDatabasePath: '${folder.path}${Platform.pathSeparator}nexora.db',
      config: config(),
      ids: RandomIdGenerator(),
      clock: _FixedClock(),
      schedulerInterval: const Duration(hours: 1),
      autoSyncOnSignIn: false,
      sleep: (d) async {},
      hook: hook,
      transportFactory: (c, token) {
        final user = sessions.userId ?? 'none';
        final server = TokenGate(
          servers.putIfAbsent(user, FakeSyncServer.new),
          token,
        );
        return wrap == null ? server : wrap(server);
      },
    );
    return (runtime: runtime, dir: folder, api: auth);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('nexora-s8-');
    now = DateTime.utc(2026, 11, 12, 12);
    servers = {};
    folders = 0;
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle may still be closing on Windows
    }
  });

  test('S8-01 fresh installation and first login', () async {
    final app = install();
    final active = await app.runtime.start();
    addTearDown(app.runtime.dispose);
    expect(active.userId, isNull); // local workspace, no account
    expect(app.api.signIns, 0);
    expect(servers, isEmpty); // nothing sent before sign-in

    expect(await app.runtime.signIn('a@example.test', 'pw'), isNotNull);
    await app.runtime.syncNow();

    expect(app.runtime.active.userId, userA);
    final projects = await app.runtime.active.repository.loadProjects();
    expect(projects.map((p) => p.name), ['Inbox']);
    expect(
      servers[userA]!.rows.keys.where((k) => k.startsWith('project:')),
      hasLength(1),
    );
    if (Platform.isWindows) {
      final file = File(
        '${app.dir.path}${Platform.pathSeparator}session${Platform.pathSeparator}session.dpapi',
      );
      expect(file.existsSync(), isTrue);
      final text = file.readAsStringSync();
      expect(text.contains('refresh-'), isFalse); // protected, not plain text
    }
  });

  test('S8-02 an existing SQLite v1 database is migrated from a verified copy and never synchronized', () async {
    final folder = Directory('${root.path}${Platform.pathSeparator}v1')
      ..createSync();
    createV1File('${folder.path}${Platform.pathSeparator}nexora.db', [
      "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
      v1Project('lp', version: 4, name: 'Legacy project'),
      v1Task('lt', 'lp', version: 2, title: 'Legacy task'),
    ]);
    final app = install(dir: folder);
    final local = await app.runtime.start();
    addTearDown(app.runtime.dispose);

    final report = local.db.migrationReport!;
    expect(report.fromVersion, 1);
    expect(report.backupFile, isNotNull);
    expect(
      File(report.backupFile!).existsSync(),
      isTrue,
    ); // the verified copy stays
    expect(
      local.db.raw
          .select("SELECT sync_scope FROM tasks WHERE id = 'lt'")
          .single['sync_scope'],
      'unclassified',
    );

    await app.runtime.signIn('a@example.test', 'pw');
    await app.runtime.syncNow();
    expect(
      servers[userA]!.rows.keys.any(
        (k) => k.contains('lt') || k.contains('lp'),
      ),
      isFalse,
    );

    await app.runtime.signOut();
    final back = app.runtime.active;
    expect(back.userId, isNull);
    expect((await back.repository.loadTasks()).single.title, 'Legacy task');
    expect(
      back.db.raw
          .select("SELECT version FROM tasks WHERE id = 'lt'")
          .single['version'],
      2,
    ); // never reset
  });

  test('S8-03 login after an application restart, with no network and no new sign-in', () async {
    final first = install();
    await first.runtime.start();
    await first.runtime.signIn('a@example.test', 'pw');
    await first.runtime.active.repository.saveProject(
      Project(id: _id(), name: 'Mine', position: 5),
    );
    await first.runtime.dispose();
    final signIns = first.api.signIns;

    final restarted = install(dir: first.dir, api: first.api);
    final active = await restarted.runtime.start();
    addTearDown(restarted.runtime.dispose);

    expect(active.userId, userA);
    expect(
      (await active.repository.loadProjects()).map((p) => p.name),
      contains('Mine'),
    );
    expect(first.api.signIns, signIns);
    expect(first.api.refreshes, 0);
  });

  test('S8-04 logout removes the protected session; another account then signs in cleanly', () async {
    final app = install();
    await app.runtime.start();
    addTearDown(app.runtime.dispose);
    await app.runtime.signIn('a@example.test', 'pw');
    await app.runtime.active.repository.saveProject(
      Project(id: _id(), name: 'A data', position: 0),
    );
    await app.runtime.signOut();
    if (Platform.isWindows) {
      final file = File(
        '${app.dir.path}${Platform.pathSeparator}session${Platform.pathSeparator}session.dpapi',
      );
      expect(file.existsSync(), isFalse);
    }
    await app.runtime.signIn('b@example.test', 'pw');
    expect(app.runtime.active.userId, userB);
    expect((await app.runtime.active.repository.loadProjects()), isEmpty);
    expect(
      Directory('${app.dir.path}${Platform.pathSeparator}accounts').listSync(),
      hasLength(2),
    );
  });

  test('S8-05 two devices change the same project and converge', () async {
    final d1 = install();
    final d2 = install();
    await d1.runtime.start();
    await d2.runtime.start();
    addTearDown(d1.runtime.dispose);
    addTearDown(d2.runtime.dispose);
    await d1.runtime.signIn('a@example.test', 'pw');
    await d2.runtime.signIn('a@example.test', 'pw');
    final project = _id();
    await d1.runtime.active.repository.saveProject(
      Project(id: project, name: 'Shared', position: 1),
    );
    final task = _id();
    await d1.runtime.active.repository.saveTask(
      makeTask(id: task, projectId: project, title: 'One', notes: 'n'),
    );
    await d1.runtime.syncNow();
    await d2.runtime.syncNow();

    await d1.runtime.active.repository.saveTask(
      makeTask(id: task, projectId: project, title: 'One (d1)', notes: 'n'),
    );
    await d2.runtime.active.repository.saveTask(
      makeTask(id: task, projectId: project, title: 'One', notes: 'notes (d2)'),
    );
    for (var i = 0; i < 2; i++) {
      await d1.runtime.syncNow();
      await d2.runtime.syncNow();
    }

    for (final d in [d1, d2]) {
      final row = d.runtime.active.db.raw.select(
        'SELECT title, notes FROM tasks WHERE id = ?',
        [task],
      ).single;
      expect(row['title'], 'One (d1)');
      expect(row['notes'], 'notes (d2)');
    }
  });

  test(
    'S8-06 offline changes survive and synchronize when the network returns',
    () async {
      var offline = true;
      final app = install(wrap: (inner) => _Switch(inner, () => offline));
      await app.runtime.start();
      addTearDown(app.runtime.dispose);
      await app.runtime.signIn('a@example.test', 'pw');
      final p = _id();
      await app.runtime.active.repository.saveProject(
        Project(id: p, name: 'Offline', position: 1),
      );
      await app.runtime.active.repository.saveTask(
        makeTask(id: _id(), projectId: p, title: 'Typed offline'),
      );

      final first = await app.runtime.syncNow();
      expect(first.phase, SyncPhase.retrying);
      expect(first.pending, greaterThan(0));

      offline = false;
      final second = await app.runtime.syncNow();
      expect(second.phase, SyncPhase.idle);
      expect(second.pending, 0);
      expect(servers[userA]!.rows.keys, contains('project:$p'));
    },
  );

  test('S8-07 a conflict is announced and resolved by the user', () async {
    final d1 = install();
    final d2 = install();
    await d1.runtime.start();
    await d2.runtime.start();
    addTearDown(d1.runtime.dispose);
    addTearDown(d2.runtime.dispose);
    await d1.runtime.signIn('a@example.test', 'pw');
    await d2.runtime.signIn('a@example.test', 'pw');
    final p = _id(), t = _id();
    await d1.runtime.active.repository.saveProject(
      Project(id: p, name: 'P', position: 1),
    );
    await d1.runtime.active.repository.saveTask(
      makeTask(id: t, projectId: p, title: 'Original'),
    );
    await d1.runtime.syncNow();
    await d2.runtime.syncNow();
    await d1.runtime.active.repository.saveTask(
      makeTask(id: t, projectId: p, title: 'From d1'),
    );
    await d2.runtime.active.repository.saveTask(
      makeTask(id: t, projectId: p, title: 'From d2'),
    );
    await d1.runtime.syncNow();

    final status = await d2.runtime.syncNow();

    expect(status.openConflicts, 1); // announced
    expect(status.needsAttention, isTrue);
    expect(
      d2.runtime.active.db.raw.select('SELECT title FROM tasks WHERE id = ?', [
        t,
      ]).single['title'],
      'From d2',
    ); // untouched
    final conflict = d2.runtime.active.engine!.outbox
        .conflictsNeedingAction()
        .single;
    await d2.runtime.active.engine!.resolveConflict(
      conflict['id']! as String,
      ConflictChoice.useServer,
    );
    expect(
      d2.runtime.active.db.raw.select('SELECT title FROM tasks WHERE id = ?', [
        t,
      ]).single['title'],
      'From d1',
    );
    expect((await d2.runtime.syncNow()).openConflicts, 0);
  });

  test(
    'S8-08 a revoked device stops synchronizing and keeps its data',
    () async {
      final d1 = install();
      final d2 = install();
      await d1.runtime.start();
      await d2.runtime.start();
      addTearDown(d1.runtime.dispose);
      addTearDown(d2.runtime.dispose);
      await d1.runtime.signIn('a@example.test', 'pw');
      await d2.runtime.signIn('a@example.test', 'pw');
      await d1.runtime.syncNow();
      await d2.runtime.syncNow();
      await d2.runtime.active.repository.saveProject(
        Project(id: _id(), name: 'Only on d2', position: 9),
      );

      await d1.runtime.active.engine!.revokeDevice(
        d2.runtime.active.engine!.outbox.deviceId(),
      );
      final status = await d2.runtime.syncNow();

      expect(status.phase, SyncPhase.deviceRevoked);
      expect(
        (await d2.runtime.active.repository.loadProjects()).map((p) => p.name),
        contains('Only on d2'),
      );
      expect(
        servers[userA]!.rows.values.any((r) => r['name'] == 'Only on d2'),
        isFalse,
      );
    },
  );

  test(
    'S8-09 a crash during push is recovered after restart without duplicates',
    () async {
      var crash = true;
      final app = install(
        hook: (point) async {
          if (crash && point == 'after_push_response') throw const _Crash();
        },
      );
      await app.runtime.start();
      await app.runtime.signIn('a@example.test', 'pw');
      final p = _id();
      await app.runtime.active.repository.saveProject(
        Project(id: p, name: 'Crash', position: 1),
      );
      await expectLater(app.runtime.syncNow(), throwsA(isA<_Crash>()));
      await app.runtime.dispose();
      crash = false;

      final restarted = install(dir: app.dir, api: app.api);
      await restarted.runtime.start();
      addTearDown(restarted.runtime.dispose);
      final status = await restarted.runtime.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(servers[userA]!.rows['project:$p']!['version'], 1);
      expect(status.pending, 0);
    },
  );

  test(
    'S8-10 a crash during pull applies nothing twice and loses nothing',
    () async {
      final d1 = install();
      await d1.runtime.start();
      addTearDown(d1.runtime.dispose);
      await d1.runtime.signIn('a@example.test', 'pw');
      final p = _id();
      await d1.runtime.active.repository.saveProject(
        Project(id: p, name: 'Big', position: 1),
      );
      for (var i = 0; i < 30; i++) {
        await d1.runtime.active.repository.saveTask(
          makeTask(id: _id(), projectId: p, title: 'T$i'),
        );
      }
      await d1.runtime.syncNow();

      var crash = true;
      final d2 = install(
        hook: (point) async {
          if (crash && point == 'after_pull_apply') throw const _Crash();
        },
      );
      await d2.runtime.start();
      await d2.runtime.signIn('a@example.test', 'pw');
      await expectLater(d2.runtime.syncNow(), throwsA(isA<_Crash>()));
      await d2.runtime.dispose();
      crash = false;
      final back = install(dir: d2.dir, api: d2.api);
      await back.runtime.start();
      addTearDown(back.runtime.dispose);

      final status = await back.runtime.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(
        back.runtime.active.db.raw
            .select('SELECT COUNT(*) AS n FROM tasks')
            .single['n'],
        30,
      );
    },
  );

  test('S8-11 an expired token is refreshed; a revoked session keeps the work and resumes after sign-in', () async {
    final app = install();
    await app.runtime.start();
    addTearDown(app.runtime.dispose);
    await app.runtime.signIn('a@example.test', 'pw');
    await app.runtime.syncNow();
    now = now.add(
      const Duration(hours: 2),
    ); // access token expired, refresh token fine
    final p1 = _id();
    await app.runtime.active.repository.saveProject(
      Project(id: p1, name: 'After expiry', position: 1),
    );
    expect((await app.runtime.syncNow()).phase, SyncPhase.idle);
    expect(app.api.refreshes, 1);
    expect(servers[userA]!.rows.keys, contains('project:$p1'));

    now = now.add(const Duration(hours: 2));
    app.api.refreshFailures.add(const AuthSessionRevoked('session_not_found'));
    final p2 = _id();
    await app.runtime.active.repository.saveProject(
      Project(
        id: p2,
        name: 'Written while signed out by the server',
        position: 2,
      ),
    );
    final status = await app.runtime.syncNow();
    expect(status.phase, SyncPhase.authRequired);
    expect(
      (await app.runtime.active.repository.loadProjects()).map((p) => p.id),
      contains(p2),
    );
    expect(servers[userA]!.rows.keys, isNot(contains('project:$p2')));

    await app.runtime.signIn('a@example.test', 'pw');
    expect((await app.runtime.syncNow()).phase, SyncPhase.idle);
    expect(servers[userA]!.rows.keys, contains('project:$p2'));
  });

  test('S8-12 an invalid cursor is reset without losing local data', () async {
    final app = install();
    await app.runtime.start();
    addTearDown(app.runtime.dispose);
    await app.runtime.signIn('a@example.test', 'pw');
    final p = _id();
    await app.runtime.active.repository.saveProject(
      Project(id: p, name: 'Keep', position: 1),
    );
    await app.runtime.syncNow();
    app.runtime.active.db.raw.execute(
      'UPDATE sync_state SET cursor = 9000000000 WHERE singleton = 1',
    );

    final status = await app.runtime.syncNow();

    expect(status.phase, SyncPhase.idle);
    expect(
      (await app.runtime.active.repository.loadProjects()).map((x) => x.id),
      contains(p),
    );
  });

  test('S8-13 tree delete: the size limit is refused locally and nothing is deleted; at the limit it works', () async {
    final app = install();
    await app.runtime.start();
    addTearDown(app.runtime.dispose);
    await app.runtime.signIn('a@example.test', 'pw');
    final repo = app.runtime.active.repository;
    final p = _id(), root = _id();
    await repo.saveProject(Project(id: p, name: 'Big tree', position: 1));
    await repo.saveTask(makeTask(id: root, projectId: p, title: 'root'));
    final children = <String>[];
    for (var i = 0; i < 1001; i++) {
      final id = _id();
      children.add(id);
      await repo.saveTask(
        makeTask(id: id, projectId: p, parentId: root, title: 'c$i'),
      );
    }
    await expectLater(
      repo.softDeleteTaskTree(root),
      throwsA(isA<RepositoryException>()),
    );
    expect(
      app.runtime.active.db.raw
          .select(
            'SELECT COUNT(*) AS n FROM tasks WHERE deleted_at IS NOT NULL',
          )
          .single['n'],
      0,
    );

    // delete one leaf, now the tree is exactly at the limit
    await repo.softDeleteTask(children.first);
    await repo.softDeleteTaskTree(root);
    final status = await app.runtime.syncNow();
    expect(status.phase, SyncPhase.idle, reason: status.code);
    final deleted = servers[userA]!.rows.values
        .where((r) => r['deleted_at'] != null)
        .length;
    expect(deleted, 1002); // root + 1000 children + the one leaf deleted first
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Fails every call while [offline] says so (the network disappears).
final class _Switch implements SyncTransport {
  _Switch(this.inner, this.offline);

  final SyncTransport inner;
  final bool Function() offline;

  void _check() {
    if (offline()) throw const SyncNetworkFailure('offline');
  }

  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) async {
    _check();
    return inner.registerDevice(deviceId, label: label);
  }

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) async {
    _check();
    return inner.push(deviceId, operations);
  }

  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) async {
    _check();
    return inner.pull(deviceId, cursor, limit: limit);
  }

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) async {
    _check();
    return inner.resolveConflict(
      deviceId: deviceId,
      operationId: operationId,
      conflictId: conflictId,
      resolution: resolution,
      values: values,
    );
  }

  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) async {
    _check();
    return inner.revokeDevice(deviceId, targetDeviceId);
  }
}
