import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/sync/sync_engine.dart';
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

import '../support/fake_sync_server.dart' show FaultyTransport, PushFault;
import '../support/task_fixtures.dart';
import '../support/v1_database.dart';
import 'pg_harness.dart';

/// Two independent local SQLite databases, the real S5 storage, the real S6 engine
/// and the real S1-S4 server on a disposable PostgreSQL 17. Skipped unless
/// NEXORA_E2E_PG=1 (the supabase-tests / e2e workflow sets it).
late String _database;
late Directory _dir;
final _ids = RandomIdGenerator();
String _id() => _ids.nextId();
var _files = 0;

final class _Crash implements Exception {
  const _Crash();
}

final class _Node {
  _Node(
    this.path,
    this.db,
    this.repo,
    this.outbox,
    this.state,
    this.pull,
    this.engine,
  );

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
  SyncTransport transport,
  String user, {
  String? path,
  Future<String?> Function()? userId,
  SyncEngineConfig config = const SyncEngineConfig(),
  SyncHook? hook,
}) {
  _files++;
  final file = path ?? '${_dir.path}${Platform.pathSeparator}n$_files.db';
  final db = LocalDatabase.open(file);
  addTearDown(() {
    try {
      db.close();
    } on Object {
      // closed by the test
    }
  });
  final repo = SqliteTaskRepository(
    db,
    ownerId: 'local-$_files',
    now: _clock,
    ids: RandomIdGenerator(),
  );
  final outbox = OutboxStore(db, ids: RandomIdGenerator(), now: _clock);
  final state = SyncStateStore(db, now: _clock);
  final pull = PullApplier(db, now: _clock);
  final engine = SyncEngine(
    transport: transport,
    outbox: outbox,
    state: state,
    pull: pull,
    userId: userId ?? () async => user,
    ids: RandomIdGenerator(),
    enabled: true,
    config: config,
    sleep: (d) async {},
    hook: hook,
  );
  return _Node(file, db, repo, outbox, state, pull, engine);
}

Future<String> _newUser({bool anonymous = false}) async {
  final id = _id();
  await mustPsql(
    _database,
    "insert into auth.users(id, is_anonymous) values ('$id', $anonymous);",
  );
  return id;
}

PsqlTransport _transport(String user) =>
    PsqlTransport(database: _database, userId: user);

Future<String> _q(String sql) => mustPsql(_database, sql);

Future<void> _converge(List<_Node> nodes) async {
  for (var round = 0; round < 2; round++) {
    for (final n in nodes) {
      final status = await n.engine.syncNow();
      expect(status.phase, SyncPhase.idle, reason: 'converge: ${status.code}');
    }
  }
}

void main() {
  setUpAll(() async {
    if (!e2eEnabled) {
      return;
    }
    _database = await createE2eDatabase();
  });
  tearDownAll(() async {
    if (e2eEnabled) {
      await dropE2eDatabase(_database);
    }
  });
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-e2e-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  final skip = e2eEnabled
      ? null
      : 'set NEXORA_E2E_PG=1 with a PostgreSQL 17 server to run';

  test(
    '1. device A creates a project and tasks; device B receives them',
    () async {
      final user = await _newUser();
      final a = _node(_transport(user), user);
      final b = _node(_transport(user), user);
      final p = _id(), t1 = _id(), t2 = _id();
      await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
      await a.repo.saveTask(
        makeTask(id: t1, projectId: p, title: 'One', notes: 'first'),
      );
      await a.repo.saveTask(
        makeTask(id: t2, projectId: p, parentId: t1, title: 'Two'),
      );

      expect((await a.engine.syncNow()).phase, SyncPhase.idle);
      expect((await b.engine.syncNow()).phase, SyncPhase.idle);

      expect(
        await _q("select count(*) from public.tasks where owner_id = '$user'"),
        '2',
      );
      expect(b.project(p)['name'], 'Home');
      expect(b.task(t2)['parent_id'], t1);
      expect(b.task(t1)['notes'], 'first');
      expect(
        '${b.task(t1)['version']}',
        await _q("select version from public.tasks where id = '$t1'"),
      );
      expect(b.task(t1)['sync_scope'], 'synced');
      expect((await b.repo.loadTasks()).map((t) => t.title).toSet(), {
        'One',
        'Two',
      });
    },
    skip: skip,
  );

  test('2. independent offline edits reconcile', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), t = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(
      makeTask(id: t, projectId: p, title: 'One', notes: 'n'),
    );
    await _converge([a, b]);
    await a.repo.saveTask(
      makeTask(id: t, projectId: p, title: 'One (A)', notes: 'n'),
    );
    await b.repo.saveTask(
      makeTask(
        id: t,
        projectId: p,
        title: 'One',
        notes: 'notes (B)',
        status: TaskStatus.inProgress,
      ),
    );

    await _converge([a, b]);

    for (final n in [a, b]) {
      expect(n.task(t)['title'], 'One (A)');
      expect(n.task(t)['notes'], 'notes (B)');
      expect(n.task(t)['status'], 'in_progress');
    }
    expect(
      await _q(
        "select title || '|' || notes from public.tasks where id = '$t'",
      ),
      'One (A)|notes (B)',
    );
    expect(
      await _q(
        "select count(*) from public.sync_conflicts where user_id = '$user'",
      ),
      '0',
    );
  }, skip: skip);

  test('3. the same field edited on two devices: conflict evidence survives every resolution', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), useServer = _id(), keepLocal = _id(), merge = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    for (final t in [useServer, keepLocal, merge]) {
      await a.repo.saveTask(makeTask(id: t, projectId: p, title: 'Original'));
    }
    await _converge([a, b]);
    for (final t in [useServer, keepLocal, merge]) {
      await a.repo.saveTask(makeTask(id: t, projectId: p, title: 'A $t'));
      await b.repo.saveTask(makeTask(id: t, projectId: p, title: 'B $t'));
    }
    await a.engine.syncNow();
    await b.engine.syncNow();

    // evidence on the server and in B's local mirror, with B's data untouched
    expect(
      await _q(
        "select count(*) from public.sync_conflicts where user_id = '$user' and status = 'open'",
      ),
      '3',
    );
    expect(b.engine.status.openConflicts, 3);
    expect(b.task(useServer)['title'], 'B $useServer');
    final byEntity = {
      for (final c in b.outbox.conflictsNeedingAction())
        c['entity_id']: c['id']! as String,
    };
    expect(
      await _q(
        "select server_value::text from public.sync_conflicts where entity_id = '$useServer'",
      ),
      contains('A $useServer'),
    );
    expect(
      await _q(
        "select client_value::text from public.sync_conflicts where entity_id = '$useServer'",
      ),
      contains('B $useServer'),
    );

    await b.engine.resolveConflict(
      byEntity[useServer]!,
      ConflictChoice.useServer,
    );
    await b.engine.resolveConflict(
      byEntity[keepLocal]!,
      ConflictChoice.keepLocal,
    );
    await b.engine.resolveConflict(
      byEntity[merge]!,
      ConflictChoice.merge,
      values: {'title': 'merged'},
    );
    await _converge([a, b]);

    for (final n in [a, b]) {
      expect(n.task(useServer)['title'], 'A $useServer');
      expect(n.task(keepLocal)['title'], 'B $keepLocal');
      expect(n.task(merge)['title'], 'merged');
    }
    expect(
      await _q(
        "select string_agg(status, ',' order by status) from public.sync_conflicts where user_id = '$user'",
      ),
      'resolved_client,resolved_merged,resolved_server',
    );
    // both original values survive in the immutable record after resolution
    expect(
      await _q(
        "select client_value::text from public.sync_conflicts where entity_id = '$keepLocal'",
      ),
      contains('B $keepLocal'),
    );
    expect(
      await _q(
        "select server_value::text from public.sync_conflicts where entity_id = '$keepLocal'",
      ),
      contains('A $keepLocal'),
    );
    expect(b.state.counts().openConflicts, 0);
  }, skip: skip);

  test('3b. an edit of a deleted task is recreated as a copy; the tombstone stays', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), t = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(makeTask(id: t, projectId: p, title: 'Doomed'));
    await _converge([a, b]);
    await a.repo.softDeleteTask(t);
    await a.engine.syncNow();
    await b.repo.saveTask(
      makeTask(id: t, projectId: p, title: 'Precious edit'),
    );
    await b.engine.syncNow();
    final conflict = b.outbox.conflictsNeedingAction().single;
    expect(conflict['kind'], 'edit_deleted');

    await b.engine.resolveConflict(
      conflict['id']! as String,
      ConflictChoice.recreateCopy,
    );
    await _converge([a, b]);

    expect(
      await _q(
        "select count(*) from public.tasks where owner_id = '$user' and title = 'Precious edit' and deleted_at is null",
      ),
      '1',
    );
    expect(
      await _q(
        "select deleted_at is not null from public.tasks where id = '$t'",
      ),
      't',
    );
    final copy = await _q(
      "select id from public.tasks where title = 'Precious edit' and owner_id = '$user'",
    );
    expect(a.task(copy)['title'], 'Precious edit');
  }, skip: skip);

  test('4. a response lost after the server committed is replayed idempotently', () async {
    final user = await _newUser();
    final faulty = FaultyTransport(_transport(user))
      ..pushFaults.add(
        const PushFault(
          SyncNetworkFailure('connection reset'),
          afterCommit: true,
        ),
      );
    final a = _node(faulty, user);
    final p = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));

    final first = await a.engine.syncNow();
    expect(first.phase, SyncPhase.retrying);
    expect(
      await _q("select count(*) from public.projects where id = '$p'"),
      '1',
    ); // it did commit
    final second = await a.engine.syncNow();

    expect(second.phase, SyncPhase.idle);
    expect(
      await _q("select version from public.projects where id = '$p'"),
      '1',
    );
    expect(
      await _q(
        "select count(*) from public.sync_operations where user_id = '$user' and entity_id = '$p'",
      ),
      '1',
    );
    expect(a.project(p)['version'], 1);
    expect(a.rows('SELECT state FROM sync_outbox').single['state'], 'applied');
  }, skip: skip);

  test('5. a process crash during synchronization recovers on restart', () async {
    final user = await _newUser();
    var crash = true;
    final a = _node(
      _transport(user),
      user,
      hook: (point) async {
        if (crash && point == 'after_push_response') {
          throw const _Crash();
        }
      },
    );
    final p = _id(), t = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(makeTask(id: t, projectId: p, title: 'One'));

    await expectLater(a.engine.syncNow(), throwsA(isA<_Crash>()));
    expect(
      a.rows('SELECT state FROM sync_outbox WHERE state = ?', ['in_flight']),
      hasLength(1),
    );
    a.db.close();
    crash = false;

    final restarted = _node(_transport(user), user, path: a.path);
    expect((await restarted.engine.syncNow()).phase, SyncPhase.idle);

    expect(
      await _q(
        "select count(*) from public.sync_operations where user_id = '$user' and status = 'applied'",
      ),
      '2',
    );
    expect(
      await _q("select count(*) from public.projects where id = '$p'"),
      '1',
    );
    expect(
      restarted.rows('SELECT COUNT(*) AS n FROM sync_outbox WHERE state = ?', [
        'applied',
      ]).single['n'],
      2,
    );
    expect(restarted.state.counts().pending, 0);
  }, skip: skip);

  test('6. deleting a task tree propagates atomically and orphans nothing', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), root = _id(), c1 = _id(), c2 = _id(), g1 = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(makeTask(id: root, projectId: p, title: 'root'));
    await a.repo.saveTask(
      makeTask(id: c1, projectId: p, parentId: root, title: 'c1'),
    );
    await a.repo.saveTask(
      makeTask(id: c2, projectId: p, parentId: root, title: 'c2'),
    );
    await a.repo.saveTask(
      makeTask(id: g1, projectId: p, parentId: c1, title: 'g1'),
    );
    await _converge([a, b]);

    await a.repo.softDeleteTaskTree(root);
    await _converge([a, b]);

    expect(
      await _q(
        "select count(*) from public.tasks where owner_id = '$user' and deleted_at is not null",
      ),
      '4',
    );
    expect(
      await _q(
        "select count(*) from public.tasks t where t.deleted_at is null and t.owner_id = '$user' and t.parent_id in (select id from public.tasks where deleted_at is not null)",
      ),
      '0',
    );
    for (final id in [root, c1, c2, g1]) {
      expect(b.task(id)['deleted_at'], isNotNull);
    }
    expect(await b.repo.loadTasks(), isEmpty);
    expect(
      await _q(
        "select count(*) from public.sync_operations where user_id = '$user' and op_type = 'delete'",
      ),
      '1',
    );
  }, skip: skip);

  test('6b. a child added on another device stops the tree delete; nothing is deleted', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), root = _id(), c1 = _id(), late = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(makeTask(id: root, projectId: p, title: 'root'));
    await a.repo.saveTask(
      makeTask(id: c1, projectId: p, parentId: root, title: 'c1'),
    );
    await _converge([a, b]);
    await a.repo.softDeleteTaskTree(root);
    await b.repo.saveTask(
      makeTask(id: late, projectId: p, parentId: root, title: 'late child'),
    );
    await b.engine.syncNow();

    await a.engine.syncNow();

    expect(
      await _q(
        "select count(*) from public.tasks where owner_id = '$user' and deleted_at is not null",
      ),
      '0',
    );
    expect(a.engine.status.openConflicts, 1);
    final conflict = a.outbox.conflictsNeedingAction().single;
    expect(conflict['kind'], 'parent_has_live_children');
    await a.engine.resolveConflict(
      conflict['id']! as String,
      ConflictChoice.useServer,
    );
    expect(a.task(root)['deleted_at'], isNull);
    expect(a.task(c1)['deleted_at'], isNull);
  }, skip: skip);

  test('7. a revoked device cannot continue synchronizing and keeps its data', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), t = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(makeTask(id: t, projectId: p, title: 'One'));
    await _converge([a, b]);
    await b.repo.saveTask(
      makeTask(id: t, projectId: p, title: 'B offline edit'),
    );

    await a.engine.revokeDevice(b.outbox.deviceId());
    final status = await b.engine.syncNow();

    expect(status.phase, SyncPhase.deviceRevoked);
    expect(status.pending, 1);
    expect(b.task(t)['title'], 'B offline edit');
    expect(
      await _q(
        "select revoked_at is not null from public.devices where id = '${b.outbox.deviceId()}'",
      ),
      't',
    );
    expect(
      await _q("select title from public.tasks where id = '$t'"),
      'One',
    ); // B's edit never arrived
    expect((await a.engine.syncNow()).phase, SyncPhase.idle);
  }, skip: skip);

  test(
    '8. local-only and unclassified records never reach the server',
    () async {
      final user = await _newUser();
      final legacy = '${_dir.path}${Platform.pathSeparator}legacy.db';
      createV1File(legacy, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        v1Project('lp', version: 4, name: 'Legacy project'),
        v1Task('lt', 'lp', version: 2, title: 'Legacy task'),
        v1Op('x', 'task', 'lt', v1TaskPayload('lt', 'lp'), state: 'sent'),
      ]);
      final l = _node(_transport(user), user, path: legacy);
    await l.repo.saveTask(makeTask(id: _id(), projectId: 'lp', title: 'under legacy'));
    final a = _node(_transport(user), user);
    final demo = buildDemoData(const CalendarDate(2026, 11, 12));
    await a.repo.seedDemoData(projects: demo.projects, tasks: demo.tasks);
    await a.repo.saveTask(makeTask(id: _id(), projectId: demo.projects.first.id, title: 'under demo'));
    final real = _id();
    await a.repo.saveProject(Project(id: real, name: 'Synchronized', position: 9));

    expect((await l.engine.syncNow()).phase, SyncPhase.idle);
    expect((await a.engine.syncNow()).phase, SyncPhase.idle);

    expect(await _q("select count(*) from public.projects where owner_id = '$user'"), '1');
    expect(await _q("select count(*) from public.tasks where owner_id = '$user'"), '0');
    expect(l.task('lt')['version'], 2);
    expect(l.rows("SELECT COUNT(*) AS n FROM tasks WHERE sync_scope <> 'synced'").single['n'], greaterThan(1));
    expect(a.rows("SELECT COUNT(*) AS n FROM tasks WHERE sync_scope <> 'synced'").single['n'], greaterThan(1));
  }, skip: skip);

  test('10. a server-side rejection cannot silently lose a client change', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id(), t = _id(), late = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.repo.saveTask(makeTask(id: t, projectId: p, title: 'One'));
    await _converge([a, b]);
    await a.repo.softDeleteTaskTree(p.isEmpty ? t : t);
    await a.repo.softDeleteProjectTree(p);
    await a.engine.syncNow();
    await b.repo.saveTask(
      makeTask(id: late, projectId: p, title: 'Written while offline'),
    );

    final status = await b.engine.syncNow();

    expect(status.rejected, 1);
    expect(status.needsAttention, isTrue);
    expect(b.task(late)['title'], 'Written while offline');
    expect(
      b.outbox.rejectedNeedingAction().single['error_code'],
      'parent_invalid',
    );
    expect(
      await _q("select count(*) from public.tasks where id = '$late'"),
      '0',
    );
    expect(
      await _q(
        "select count(*) from public.sync_operations where user_id = '$user' and status = 'rejected'",
      ),
      '1',
    ); // recorded as history
  }, skip: skip);

  test('11. a large account is pulled in bounded pages', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(
      _transport(user),
      user,
      config: const SyncEngineConfig(pullPageLimit: 100),
    );
    final p = _id();
    await a.repo.saveProject(Project(id: p, name: 'Big', position: 0));
    for (var i = 0; i < 230; i++) {
      await a.repo.saveTask(
        makeTask(id: _id(), projectId: p, title: 'T$i', position: i),
      );
    }
    expect((await a.engine.syncNow()).phase, SyncPhase.idle);

    expect((await b.engine.syncNow()).phase, SyncPhase.idle);

    expect(b.rows('SELECT COUNT(*) AS n FROM tasks').single['n'], 230);
    expect(b.state.counts().staged, 0);
    expect(
      await _q("select count(*) from public.tasks where owner_id = '$user'"),
      '230',
    );
  }, skip: skip);

  test('12. an unknown cursor is reset and the pull starts over', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final p = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await a.engine.syncNow();
    a.db.raw.execute(
      'UPDATE sync_state SET cursor = 9000000000 WHERE singleton = 1',
    );

    final status = await a.engine.syncNow();

    expect(status.phase, SyncPhase.idle);
    expect(a.state.cursor(), lessThan(9000000000));
  }, skip: skip);

  test('13. both devices synchronizing at the same time converge', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    final b = _node(_transport(user), user);
    final p = _id();
    await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
    await _converge([a, b]);
    final ta = <String>[], tb = <String>[];
    for (var i = 0; i < 12; i++) {
      final x = _id(), y = _id();
      ta.add(x);
      tb.add(y);
      await a.repo.saveTask(makeTask(id: x, projectId: p, title: 'A$i'));
      await b.repo.saveTask(makeTask(id: y, projectId: p, title: 'B$i'));
    }

    await Future.wait([a.engine.syncNow(), b.engine.syncNow()]);
    await _converge([a, b]);

    for (final n in [a, b]) {
      expect(n.rows('SELECT COUNT(*) AS n FROM tasks').single['n'], 24);
      expect(n.state.counts().pending, 0);
    }
    expect(
      await _q("select count(*) from public.tasks where owner_id = '$user'"),
      '24',
    );
  }, skip: skip);
}
