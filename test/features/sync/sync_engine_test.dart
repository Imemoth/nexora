import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/sync/backoff.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_feature.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/pull_applier.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../support/fake_sync_server.dart';
import '../../support/sequential_id_generator.dart';
import '../../support/task_fixtures.dart';
import '../../support/v1_database.dart';

/// S6 engine tests against the in-memory fake server (deterministic, no network).
late Directory _dir;
var _files = 0;

final class _Crash implements Exception {
  const _Crash();
}

final class _Node {
  _Node(
    this.name,
    this.path,
    this.db,
    this.repo,
    this.outbox,
    this.state,
    this.pull,
    this.engine,
  );

  final String name;
  final String path;
  final LocalDatabase db;
  final SqliteTaskRepository repo;
  final OutboxStore outbox;
  final SyncStateStore state;
  final PullApplier pull;
  final SyncEngine engine;

  List<Map<String, Object?>> rows(
    String sql, [
    List<Object?> params = const [],
  ]) => [
    for (final r in db.raw.select(sql, params))
      {for (final k in r.keys) k: r[k]},
  ];

  Map<String, Object?> task(String id) =>
      rows('SELECT * FROM tasks WHERE id = ?', [id]).single;
  Map<String, Object?> project(String id) =>
      rows('SELECT * FROM projects WHERE id = ?', [id]).single;
}

DateTime _clock() => DateTime.utc(2026, 11, 12, 10);

_Node _node(
  String name,
  SyncTransport transport, {
  String? path,
  bool enabled = true,
  Future<String?> Function()? userId,
  SyncEngineConfig config = const SyncEngineConfig(),
  Backoff? backoff,
  List<Duration>? sleeps,
  SyncHook? hook,
}) {
  _files++;
  final file = path ?? '${_dir.path}${Platform.pathSeparator}$name-$_files.db';
  final db = LocalDatabase.open(file);
  addTearDown(() {
    try {
      db.close();
    } on Object {
      // already closed by the test
    }
  });
  List<String> ids(String p) => [
    for (var i = 0; i < 5000; i++) '$p-$name-$_files-$i',
  ];
  final repo = SqliteTaskRepository(
    db,
    ownerId: 'local-$name',
    now: _clock,
    ids: SequentialIdGenerator(ids('r')),
  );
  final outbox = OutboxStore(
    db,
    ids: SequentialIdGenerator(ids('o')),
    now: _clock,
  );
  final state = SyncStateStore(db, now: _clock);
  final pull = PullApplier(db, now: _clock);
  final engine = SyncEngine(
    transport: transport,
    outbox: outbox,
    state: state,
    pull: pull,
    userId: userId ?? () async => 'user-1',
    ids: SequentialIdGenerator(ids('e')),
    enabled: enabled,
    config: config,
    backoff: backoff ?? Backoff(jitter: 0),
    sleep: (d) async => sleeps?.add(d),
    hook: hook,
  );
  return _Node(name, file, db, repo, outbox, state, pull, engine);
}

Future<void> _seed(_Node n) async {
  await n.repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
  await n.repo.saveTask(
    makeTask(id: 't1', projectId: 'p1', title: 'One', notes: 'n1'),
  );
  await n.repo.saveTask(
    makeTask(id: 't2', projectId: 'p1', parentId: 't1', title: 'Two'),
  );
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-sync-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('feature flag, identity, status', () {
    test('the flag is off by default', () {
      expect(syncFeatureEnabled, isFalse);
    });

    test('with the flag off nothing touches the transport', () async {
      final server = FakeSyncServer();
      final a = _node('a', server, enabled: false);
      await _seed(a);

      final status = await a.engine.syncNow();

      expect(status.phase, SyncPhase.disabled);
      expect(server.log, isEmpty);
      expect(a.state.counts().pending, 3);
    });

    test('the default engine honours the build-time flag (off)', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final off = SyncEngine(
        transport: server,
        outbox: a.outbox,
        state: a.state,
        pull: a.pull,
        userId: () async => 'user-1',
        ids: SequentialIdGenerator(['x']),
      );

      expect((await off.syncNow()).phase, SyncPhase.disabled);
      expect(server.log, isEmpty);
    });

    test('signed out: nothing is sent and pending work waits', () async {
      final server = FakeSyncServer();
      final a = _node('a', server, userId: () async => null);
      await _seed(a);

      final status = await a.engine.syncNow();

      expect(status.phase, SyncPhase.authRequired);
      expect(status.pending, 3);
      expect(server.log, isEmpty);
    });

    test('a database bound to one account refuses another account', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await _seed(a);
      await a.engine.syncNow();
      server.log.clear();
      final other = SyncEngine(
        transport: server,
        outbox: a.outbox,
        state: a.state,
        pull: a.pull,
        userId: () async => 'someone-else',
        ids: SequentialIdGenerator(['y']),
        enabled: true,
      );

      final status = await other.syncNow();

      expect(status.phase, SyncPhase.error);
      expect(status.code, contains('another account'));
      expect(server.log, isEmpty);
    });

    test('the status stream shows the cycle and the counts', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await _seed(a);
      final seen = <SyncPhase>[];
      final sub = a.engine.statuses.listen((s) => seen.add(s.phase));

      final done = await a.engine.syncNow();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(seen, [SyncPhase.syncing, SyncPhase.idle]);
      expect(done.pending, 0);
      expect(done.lastSyncedAt, isNotNull);
    });

    test('concurrent syncNow calls share one cycle', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await _seed(a);

      final results = await Future.wait([
        a.engine.syncNow(),
        a.engine.syncNow(),
      ]);

      expect(identical(results[0], results[1]), isTrue);
      expect(server.log.where((l) => l == 'register'), hasLength(1));
    });
  });

  group('push', () {
    test(
      'creates reach the server in dependency order and versions come back',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        await _seed(a);

        final status = await a.engine.syncNow();

        expect(status.phase, SyncPhase.idle);
        expect(server.rows.keys.toSet(), {'project:p1', 'task:t1', 'task:t2'});
        expect(a.project('p1')['version'], 1);
        expect(a.task('t2')['version'], 1);
        expect(server.log.where((l) => l.startsWith('push')).toList(), [
          'push:1',
          'push:1',
          'push:1',
        ]);
        server.log.clear();
        await a.engine.syncNow();
        expect(server.log.where((l) => l.startsWith('push')), isEmpty);
      },
    );

    test('ordered batches: 100 operations per call', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await a.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await a.engine.syncNow();
      for (var i = 0; i < 105; i++) {
        await a.repo.saveTask(
          makeTask(id: 'b$i', projectId: 'p1', title: 'T$i'),
        );
      }
      server.log.clear();

      await a.engine.syncNow();

      expect(server.log.where((l) => l.startsWith('push')).toList(), [
        'push:100',
        'push:5',
      ]);
      expect(server.rows.length, 106);
    });

    test('a network failure keeps the identical operations and the retry sends them again', () async {
      final server = FakeSyncServer();
      final fault = FaultyTransport(server)
        ..pushFaults.add(const PushFault(SyncNetworkFailure('timeout')));
      final a = _node('a', fault);
      await a.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final operationId = a
          .rows('SELECT operation_id FROM sync_outbox')
          .single['operation_id'];

      final first = await a.engine.syncNow();

      expect(first.phase, SyncPhase.retrying);
      expect(first.pending, 1);
      expect(server.rows, isEmpty);
      final second = await a.engine.syncNow();
      expect(second.phase, SyncPhase.idle);
      expect(a.rows('SELECT operation_id, state FROM sync_outbox').single, {
        'operation_id': operationId,
        'state': 'applied',
      });
    });

    test('a response lost after the server committed is replayed, never applied twice', () async {
      final server = FakeSyncServer();
      final fault = FaultyTransport(server)
        ..pushFaults.add(
          const PushFault(SyncNetworkFailure('reset'), afterCommit: true),
        );
      final a = _node('a', fault);
      await a.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );

      final first = await a.engine.syncNow();
      expect(first.phase, SyncPhase.retrying);
      expect(server.rows.keys, ['project:p1']); // the server did commit
      final second = await a.engine.syncNow();

      expect(second.phase, SyncPhase.idle);
      expect(server.stored.length, 1);
      expect(server.rows['project:p1']!['version'], 1);
      expect(a.project('p1')['version'], 1);
      expect(
        a.rows('SELECT state FROM sync_outbox').single['state'],
        'applied',
      );
    });

    test('an oversized batch is halved and retried', () async {
      final server = FakeSyncServer();
      final fault = FaultyTransport(server);
      final a = _node('a', fault, config: const SyncEngineConfig(maxBatch: 4));
      await a.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      // The project is acknowledged first, so the tasks can travel together.
      expect((await a.engine.syncNow()).phase, SyncPhase.idle);
      for (var i = 0; i < 8; i++) {
        await a.repo.saveTask(
          makeTask(id: 'b$i', projectId: 'p1', title: 'T$i'),
        );
      }
      fault.pushFaults.add(const PushFault(SyncServerError('batch_too_large')));
      server.log.clear();

      final status = await a.engine.syncNow();

      expect(status.phase, SyncPhase.idle);
      // The refused batch of 4 never reached the server; the first accepted
      // call carries the halved batch of 2.
      final pushes = server.log.where((l) => l.startsWith('push:')).toList();
      expect(pushes.first, 'push:2');
      expect(server.rows.length, 9);
    });

    test(
      'backoff: exponential delays between attempts, then success',
      () async {
        final server = FakeSyncServer();
        final fault = FaultyTransport(server)
          ..pushFaults.addAll(
            List.filled(3, const PushFault(SyncNetworkFailure('offline'))),
          );
        final sleeps = <Duration>[];
        final a = _node('a', fault, sleeps: sleeps);
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );

        final status = await a.engine.runWithRetry();

        expect(status.phase, SyncPhase.idle);
        expect(sleeps, [
          const Duration(seconds: 2),
          const Duration(seconds: 4),
          const Duration(seconds: 8),
        ]);
      },
    );

    test(
      'the retry budget ends in a visible retrying state with nothing lost',
      () async {
        final server = FakeSyncServer();
        final fault = FaultyTransport(server)
          ..pushFaults.addAll(
            List.filled(50, const PushFault(SyncNetworkFailure('offline'))),
          );
        final a = _node(
          'a',
          fault,
          config: const SyncEngineConfig(maxRetriesPerRun: 2),
        );
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );

        final status = await a.engine.runWithRetry();

        expect(status.phase, SyncPhase.retrying);
        expect(status.attempt, 3);
        expect(status.pending, 1);
        expect(a.project('p1')['name'], 'Home');
      },
    );

    test('an authentication failure keeps every pending change', () async {
      final server = FakeSyncServer();
      final fault = FaultyTransport(server)
        ..pushFaults.add(const PushFault(SyncAuthFailure('expired')));
      final a = _node('a', fault);
      await _seed(a);

      final status = await a.engine.syncNow();

      expect(status.phase, SyncPhase.authRequired);
      expect(status.pending, 3);
      expect(a.state.counts().inFlight, 0);
      expect(server.rows, isEmpty);
      expect(
        (await a.engine.syncNow()).phase,
        SyncPhase.idle,
      ); // signed in again
      expect(server.rows.length, 3);
    });

    test(
      'an anonymous identity is reported as such and never retried',
      () async {
        final server = FakeSyncServer();
        final fault = FaultyTransport(server)
          ..pushFaults.add(
            const PushFault(SyncAuthFailure('anonymous', anonymous: true)),
          );
        final a = _node('a', fault);
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );

        final status = await a.engine.runWithRetry();

        expect(status.phase, SyncPhase.authRequired);
        expect(status.code, 'anonymous');
      },
    );

    test(
      'a revoked device pauses synchronization and keeps its data and queue',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await a.engine.syncNow();
        server.devices[a.outbox.deviceId()] = true; // revoked elsewhere
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Renamed', position: 0),
        );
        server.log.clear();

        final status = await a.engine.syncNow();

        expect(status.phase, SyncPhase.deviceRevoked);
        expect(status.pending, 1);
        expect(a.project('p1')['name'], 'Renamed');
        expect(a.state.paused, isTrue);
        server.log.clear();
        expect((await a.engine.syncNow()).phase, SyncPhase.deviceRevoked);
        expect(server.log, isEmpty); // paused: no network at all
      },
    );

    test(
      'a refused change stays visible and the local data is untouched',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await a.engine.syncNow();
        server.otherDeviceEdit('project', 'p1', {
          'deleted_at': '2026-11-12T11:00:00+00:00',
        });
        await a.repo.saveTask(
          makeTask(id: 'late', projectId: 'p1', title: 'Written offline'),
        );

        final status = await a.engine.syncNow();

        expect(status.rejected, 1);
        expect(status.needsAttention, isTrue);
        expect(a.task('late')['title'], 'Written offline');
        expect(
          a.outbox.rejectedNeedingAction().single['error_code'],
          'parent_invalid',
        );
        expect(server.rows.containsKey('task:late'), isFalse);
      },
    );

    test('a crash after the response, before the acknowledgement, recovers on restart', () async {
      final server = FakeSyncServer();
      var crash = true;
      final a = _node(
        'a',
        server,
        hook: (point) async {
          if (point == 'after_push_response' && crash) {
            throw const _Crash();
          }
        },
      );
      await a.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );

      await expectLater(a.engine.syncNow(), throwsA(isA<_Crash>()));
      expect(
        a.rows('SELECT state FROM sync_outbox').single['state'],
        'in_flight',
      );
      a.db.close();
      crash = false;

      final b = _node('a', server, path: a.path);
      final status = await b.engine.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(server.stored.length, 1);
      expect(
        b.rows('SELECT state FROM sync_outbox').single['state'],
        'applied',
      );
      expect(b.project('p1')['version'], 1);
    });

    test(
      'local-only, demo and unclassified records never reach the server',
      () async {
        final server = FakeSyncServer();
        final legacy = '${_dir.path}${Platform.pathSeparator}legacy.db';
        createV1File(legacy, [
          "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
          v1Project('lp', version: 5, name: 'Legacy project'),
          v1Task('lt', 'lp', version: 3, title: 'Legacy task'),
          v1Op('x', 'task', 'lt', v1TaskPayload('lt', 'lp'), state: 'acked'),
        ]);
        final l = _node('l', server, path: legacy);
        await l.repo.saveTask(
          makeTask(id: 'under-legacy', projectId: 'lp', title: 'Unclassified'),
        );
        final a = _node('a', server);
        final demo = buildDemoData(const CalendarDate(2026, 11, 12));
        await a.repo.seedDemoData(projects: demo.projects, tasks: demo.tasks);
        await a.repo.saveTask(
          makeTask(
            id: 'under-demo',
            projectId: demo.projects.first.id,
            title: 'Local only',
          ),
        );
        await a.repo.saveProject(
          const Project(id: 'real', name: 'Synchronized', position: 50),
        );
        await a.repo.saveTask(
          makeTask(
            id: 'real-task',
            projectId: 'real',
            title: 'Goes to the server',
          ),
        );

        expect((await l.engine.syncNow()).phase, SyncPhase.idle);
        final status = await a.engine.syncNow();

        expect(status.phase, SyncPhase.idle);
        expect(server.rows.keys.toSet(), {'project:real', 'task:real-task'});
        expect(l.task('lt')['version'], 3); // never reset
        expect(a.task('under-demo')['sync_scope'], 'local_only');
        expect(l.task('under-legacy')['sync_scope'], 'unclassified');
      },
    );
  });

  group('pull and two devices', () {
    test('device B receives what device A created', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();

      final status = await b.engine.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(b.project('p1')['name'], 'Home');
      expect(b.task('t2')['parent_id'], 't1');
      expect(b.task('t1')['sync_scope'], 'synced');
      expect(b.task('t1')['version'], 1);
      expect((await b.repo.loadTasks()).map((t) => t.title).toSet(), {
        'One',
        'Two',
      });
      expect(b.state.counts().pending, 0);
    });

    test(
      'independent offline edits of different fields both survive',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        final b = _node('b', server);
        await _seed(a);
        await a.engine.syncNow();
        await b.engine.syncNow();
        await a.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', title: 'One (A)', notes: 'n1'),
        );
        await b.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', title: 'One', notes: 'notes (B)'),
        );

        await a.engine.syncNow();
        await b.engine.syncNow();
        await a.engine.syncNow();

        for (final n in [a, b]) {
          expect(n.task('t1')['title'], 'One (A)');
          expect(n.task('t1')['notes'], 'notes (B)');
          expect(n.task('t1')['version'], 3);
        }
        expect(server.rows['task:t1']!['title'], 'One (A)');
        expect(
          a.state.counts().openConflicts + b.state.counts().openConflicts,
          0,
        );
      },
    );

    test(
      'a pulled row never overwrites a field with an unsent local edit',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        final b = _node('b', server);
        await _seed(a);
        await a.engine.syncNow();
        await b.engine.syncNow();
        await b.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', title: 'B edit', notes: 'n1'),
        );
        await a.repo.saveTask(
          makeTask(
            id: 't1',
            projectId: 'p1',
            title: 'A edit',
            notes: 'a notes',
          ),
        );
        await a.engine.syncNow();

        final result = b.pull.applyPage(
          await server.pull(b.outbox.deviceId(), b.state.cursor()),
        );

        expect(result.preserved, 1);
        expect(b.task('t1')['title'], 'B edit'); // unsent: kept
        expect(
          b.task('t1')['notes'],
          'a notes',
        ); // not pending: taken from the server
        expect(b.task('t1')['version'], 2);
      },
    );

    test('rows that arrive before their parent wait and are applied when it arrives', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node(
        'b',
        server,
        config: const SyncEngineConfig(pullPageLimit: 1),
      );
      await _seed(a);
      await a.engine.syncNow();
      await a.repo.saveProject(
        const Project(id: 'p1', name: 'Home (renamed)', position: 0),
      );
      await a.engine
          .syncNow(); // the project now has a later change_seq than its tasks

      final status = await b.engine.syncNow();

      expect(status.phase, SyncPhase.idle);
      expect(status.staged, 0);
      expect(b.project('p1')['name'], 'Home (renamed)');
      expect(b.rows('SELECT COUNT(*) AS n FROM tasks').single['n'], 2);
    });

    test('the cursor persists and the next pull is incremental', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();
      await b.engine.syncNow();
      final cursor = b.state.cursor();
      expect(cursor, greaterThan(0));
      server.otherDeviceEdit('task', 't1', {'title': 'elsewhere'});
      server.log.clear();

      await b.engine.syncNow();

      expect(
        server.log.where((l) => l.startsWith('pull')).first,
        'pull:$cursor',
      );
      expect(b.task('t1')['title'], 'elsewhere');
      expect(b.state.cursor(), greaterThan(cursor));
    });

    test(
      'a cursor the server does not know is reset and the pull starts over',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        await _seed(a);
        await a.engine.syncNow();
        a.db.raw.execute(
          'UPDATE sync_state SET cursor = 100000 WHERE singleton = 1',
        );

        final status = await a.engine.syncNow();

        expect(status.phase, SyncPhase.idle);
        expect(a.state.cursor(), lessThan(100000));
        expect(a.project('p1')['name'], 'Home');
      },
    );

    test(
      'a server row with the id of a local-only row never touches it',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        final b = _node('b', server);
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await a.repo.saveTask(
          makeTask(id: 'same-id', projectId: 'p1', title: 'On the server'),
        );
        await a.engine.syncNow();
        final demo = buildDemoData(const CalendarDate(2026, 11, 12));
        await b.repo.seedDemoData(projects: demo.projects, tasks: demo.tasks);
        b.db.raw.execute("UPDATE tasks SET id = 'same-id' WHERE id = ?", [
          demo.tasks.first.id,
        ]);

        await b.engine.syncNow();

        expect(b.task('same-id')['title'], isNot('On the server'));
        expect(b.task('same-id')['sync_scope'], 'local_only');
      },
    );

    test(
      'a malformed pull response applies nothing and does not move the cursor',
      () async {
        final server = FakeSyncServer();
        final a = _node('a', server);
        await a.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        final before = a.state.cursor();

        expect(
          () => a.pull.applyPage({'changes': 'x'}),
          throwsA(isA<PullProtocolException>()),
        );
        expect(
          () => a.pull.applyPage({
            'changes': [
              {
                'entity_type': 'project',
                'row': {'id': 'p9', 'version': 1, 'change_seq': 5, 'name': 'X'},
              },
              {'entity_type': 'nonsense'},
            ],
            'conflicts': <Object?>[],
            'next_cursor': 9,
            'has_more': false,
          }),
          throwsA(isA<PullProtocolException>()),
        );

        expect(a.state.cursor(), before);
        expect(a.rows('SELECT id FROM projects WHERE id = ?', ['p9']), isEmpty);
      },
    );
  });

  group('conflicts', () {
    Future<(FakeSyncServer, _Node, _Node)> twoWayConflict() async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'A title', notes: 'n1'),
      );
      await b.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'B title', notes: 'n1'),
      );
      await a.engine.syncNow();
      await b.engine.syncNow();
      return (server, a, b);
    }

    test('a same-field conflict keeps both values, the local data and the evidence', () async {
      final (server, a, b) = await twoWayConflict();

      final status = b.engine.status;
      expect(status.openConflicts, 1);
      expect(status.needsAttention, isTrue);
      final conflict = b.outbox.conflictsNeedingAction().single;
      expect(conflict['kind'], 'field');
      expect(conflict['server_value_json'], contains('A title'));
      expect(conflict['client_value_json'], contains('B title'));
      expect(b.task('t1')['title'], 'B title'); // local data preserved
      expect(server.rows['task:t1']!['title'], 'A title');
      expect(a.state.counts().openConflicts, 0);
    });

    test('use server: the local change is archived and the entity follows the server', () async {
      final (server, _, b) = await twoWayConflict();
      final id = b.outbox.conflictsNeedingAction().single['id']! as String;

      await b.engine.resolveConflict(id, ConflictChoice.useServer);
      await b.engine.syncNow();

      expect(b.task('t1')['title'], 'A title');
      expect(b.state.counts().openConflicts, 0);
      expect(
        b.rows(
          "SELECT archive_reason FROM sync_outbox_archive WHERE source = 'v2'",
        ),
        isEmpty,
      ); // nothing pending to archive
      expect(server.conflicts.values.single['status'], 'resolved_server');
    });

    test(
      'keep local: the server takes the local value and both devices converge',
      () async {
        final (server, a, b) = await twoWayConflict();
        final id = b.outbox.conflictsNeedingAction().single['id']! as String;

        await b.engine.resolveConflict(id, ConflictChoice.keepLocal);
        await b.engine.syncNow();
        await a.engine.syncNow();

        expect(server.rows['task:t1']!['title'], 'B title');
        expect(a.task('t1')['title'], 'B title');
        expect(b.task('t1')['title'], 'B title');
        expect(b.state.counts().openConflicts, 0);
      },
    );

    test(
      'merge: the server and the local data hold the merged value',
      () async {
        final (server, _, b) = await twoWayConflict();
        final id = b.outbox.conflictsNeedingAction().single['id']! as String;

        await b.engine.resolveConflict(
          id,
          ConflictChoice.merge,
          values: {'title': 'A and B'},
        );
        await b.engine.syncNow();

        expect(server.rows['task:t1']!['title'], 'A and B');
        expect(b.task('t1')['title'], 'A and B');
      },
    );

    test('an edit of a deleted task can be recreated as a copy; the original stays deleted', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.repo.softDeleteTask('t2');
      await a.engine.syncNow();
      await b.repo.saveTask(
        makeTask(
          id: 't2',
          projectId: 'p1',
          parentId: 't1',
          title: 'Valuable edit',
        ),
      );
      await b.engine.syncNow();
      final conflict = b.outbox.conflictsNeedingAction().single;
      expect(conflict['kind'], 'edit_deleted');

      await b.engine.resolveConflict(
        conflict['id']! as String,
        ConflictChoice.recreateCopy,
      );
      await b.engine.syncNow();

      final copies = server.rows.entries
          .where(
            (e) =>
                e.key.startsWith('task:') &&
                e.value['title'] == 'Valuable edit',
          )
          .toList();
      expect(copies, hasLength(1));
      expect(server.rows['task:t2']!['deleted_at'], isNotNull);
      final copyId = copies.single.value['id']! as String;
      expect(b.task(copyId)['title'], 'Valuable edit');
      expect(b.task(copyId)['sync_scope'], 'synced');
      expect(b.task('t2')['deleted_at'], isNotNull);
    });

    test('a refused resolution changes nothing locally', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.repo.softDeleteTask('t2');
      await a.engine.syncNow();
      await b.repo.saveTask(
        makeTask(id: 't2', projectId: 'p1', parentId: 't1', title: 'Edit'),
      );
      await b.engine.syncNow();
      final id = b.outbox.conflictsNeedingAction().single['id']! as String;

      await expectLater(
        b.engine.resolveConflict(id, ConflictChoice.keepLocal),
        throwsA(isA<ResolveRejected>()),
      );

      expect(b.outbox.conflictsNeedingAction(), hasLength(1));
      expect(b.task('t2')['title'], 'Edit');
    });

    test(
      'a retried resolution reuses its operation id, so the server replays it',
      () async {
        final (server, _, b) = await twoWayConflict();
        final id = b.outbox.conflictsNeedingAction().single['id']! as String;
        final first = b.state.resolveOperationId('$id:resolved_server');
        expect(first, isNull);

        await b.engine.resolveConflict(id, ConflictChoice.useServer);

        expect(b.state.resolveOperationId('$id:resolved_server'), isNotNull);
        expect(
          server.stored.keys,
          contains(b.state.resolveOperationId('$id:resolved_server')),
        );
      },
    );

    test('an operation blocked by another device\'s conflict is resubmitted once it is resolved', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();
      await b.engine.syncNow();
      server.otherDeviceEdit('task', 't1', {'title': 'server side'});
      await a.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'A edit', notes: 'n1'),
      );
      await a.engine.syncNow(); // A: a field conflict on t1
      await b.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'One', notes: 'B notes'),
      );
      await b.engine
          .syncNow(); // B: rejected, the entity is blocked by A's conflict
      expect(b.state.counts().rejected, 1);
      expect(server.rows['task:t1']!['notes'], 'n1');
      final id = a.outbox.conflictsNeedingAction().single['id']! as String;

      await a.engine.resolveConflict(id, ConflictChoice.useServer);
      final status = await b.engine.syncNow();

      expect(status.rejected, 0);
      expect(server.rows['task:t1']!['notes'], 'B notes');
      expect(b.task('t1')['notes'], 'B notes');
    });
  });

  group('tree deletion and revocation', () {
    Future<(FakeSyncServer, _Node, _Node)> tree() async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.repo.saveTask(
        makeTask(id: 't3', projectId: 'p1', parentId: 't1', title: 'Three'),
      );
      await a.engine.syncNow();
      await b.engine.syncNow();
      return (server, a, b);
    }

    test('deleting a task tree is one atomic operation and nothing is orphaned elsewhere', () async {
      final (server, a, b) = await tree();
      await a.repo.softDeleteTaskTree('t1');
      expect(
        a
            .rows("SELECT op_type FROM sync_outbox WHERE state = 'pending'")
            .single['op_type'],
        'delete',
      );
      server.log.clear();

      await a.engine.syncNow();
      await b.engine.syncNow();

      expect(server.log.where((l) => l.startsWith('push')).toList(), [
        'push:1',
      ]);
      for (final id in ['t1', 't2', 't3']) {
        expect(server.rows['task:$id']!['deleted_at'], isNotNull);
        expect(b.task(id)['deleted_at'], isNotNull);
      }
      expect(await b.repo.loadTasks(), isEmpty);
      expect(a.state.counts().pending, 0);
    });

    test('a child added elsewhere makes the tree delete a conflict and deletes nothing', () async {
      final (server, a, b) = await tree();
      await a.repo.softDeleteTaskTree('t1');
      await b.repo.saveTask(
        makeTask(
          id: 'late',
          projectId: 'p1',
          parentId: 't1',
          title: 'Added by B',
        ),
      );
      await b.engine.syncNow();

      await a.engine.syncNow();

      expect(server.rows['task:t1']!['deleted_at'], isNull);
      expect(server.rows['task:t2']!['deleted_at'], isNull);
      final conflict = a.outbox.conflictsNeedingAction().single;
      expect(conflict['kind'], 'parent_has_live_children');
      // use server: the local tombstones are undone together
      await a.engine.resolveConflict(
        conflict['id']! as String,
        ConflictChoice.useServer,
      );
      for (final id in ['t1', 't2', 't3']) {
        expect(a.task(id)['deleted_at'], isNull);
      }
    });

    test('a tree with unsent descendants waits until their operations are acknowledged', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await _seed(a);
      await a.repo.softDeleteTaskTree(
        't1',
      ); // nothing was sent yet: creates, then the delete

      await a.engine.syncNow();

      expect(server.rows['task:t1']!['deleted_at'], isNotNull);
      expect(server.rows['task:t2']!['deleted_at'], isNotNull);
      expect(a.state.counts().pending, 0);
    });

    test('revoking another device stops it; its data and queue stay', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      final b = _node('b', server);
      await _seed(a);
      await a.engine.syncNow();
      await b.engine.syncNow();
      await b.repo.saveTask(
        makeTask(
          id: 't1',
          projectId: 'p1',
          title: 'B offline edit',
          notes: 'n1',
        ),
      );

      await a.engine.revokeDevice(b.outbox.deviceId());
      final status = await b.engine.syncNow();

      expect(status.phase, SyncPhase.deviceRevoked);
      expect(status.pending, 1);
      expect(b.task('t1')['title'], 'B offline edit');
      expect((await a.engine.syncNow()).phase, SyncPhase.idle);
    });

    test('a device revoking itself pauses its own synchronization', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await _seed(a);
      await a.engine.syncNow();

      await a.engine.revokeDevice(a.outbox.deviceId());

      expect(a.engine.status.phase, SyncPhase.deviceRevoked);
      expect(a.state.paused, isTrue);
    });
  });

  group('backoff', () {
    test(
      'delays grow exponentially, are capped, and jitter stays within bounds',
      () {
        final plain = Backoff(jitter: 0);
        expect(
          [for (var i = 0; i < 4; i++) plain.delay(i).inSeconds],
          [2, 4, 8, 16],
        );
        expect(plain.delay(40), const Duration(minutes: 5));
        final jittered = Backoff(jitter: 0.2);
        for (var i = 0; i < 200; i++) {
          final d = jittered.delay(3).inMilliseconds;
          expect(d, inInclusiveRange(12800, 19200));
        }
      },
    );
  });

  group('local statuses used by the UI', () {
    test('the done flag of a task still reaches the server as a derived completed_at', () async {
      final server = FakeSyncServer();
      final a = _node('a', server);
      await _seed(a);
      await a.engine.syncNow();
      await a.repo.saveTask(
        makeTask(
          id: 't1',
          projectId: 'p1',
          title: 'One',
          notes: 'n1',
          status: TaskStatus.done,
        ),
      );

      await a.engine.syncNow();

      expect(server.rows['task:t1']!['status'], 'done');
      expect(server.rows['task:t1']!['completed_at'], isNotNull);
    });
  });
}
