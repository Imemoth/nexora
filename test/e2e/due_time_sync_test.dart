import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/sync/conflicts.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_import.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/pull_applier.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import '../support/task_fixtures.dart';
import 'pg_harness.dart';

/// The optional due time across two clients, the real client storage and engine, and the real
/// migrated server on a disposable PostgreSQL (ADR 0004). Skipped unless NEXORA_E2E_PG=1.
/// Never touches a hosted project.
late String _database;
late Directory _dir;
final _ids = RandomIdGenerator();
String _id() => _ids.nextId();
var _files = 0;

DateTime _clock() => DateTime.utc(2026, 11, 16, 10);
const _d1 = CalendarDate(2026, 11, 20);
const _d2 = CalendarDate(2026, 12, 3);

final class _Node {
  _Node(this.path, this.db, this.repo, this.outbox, this.state, this.engine);

  final String path;
  final LocalDatabase db;
  final SqliteTaskRepository repo;
  final OutboxStore outbox;
  final SyncStateStore state;
  final SyncEngine engine;

  Map<String, Object?> task(String id) => {
    for (final r in db.raw.select('SELECT * FROM tasks WHERE id = ?', [id]))
      for (final k in r.keys) k: r[k],
  };

  Future<(CalendarDate?, DueTime?)> dateTime(String id) async {
    final t = (await repo.loadTasks()).firstWhere((t) => t.id == id);
    return (t.dueDate, t.dueTime);
  }

  List<String> pendingPatches() => [
    for (final r in db.raw.select(
      "SELECT payload_json FROM sync_outbox WHERE state = 'pending' ORDER BY rowid",
    ))
      r['payload_json'] as String,
  ];
}

_Node _node(SyncTransport transport, String user, {String? path}) {
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
  final state = SyncStateStore(db, now: _clock);
  final repo = SqliteTaskRepository(
    db,
    ownerId: 'local-$_files',
    now: _clock,
    ids: RandomIdGenerator(),
    // exactly what the runtime does: follow what the server reported
    dueTimeSyncs: () => state.serverSupportsDueTime,
  );
  final outbox = OutboxStore(db, ids: RandomIdGenerator(), now: _clock);
  final engine = SyncEngine(
    transport: transport,
    outbox: outbox,
    state: state,
    pull: PullApplier(db, now: _clock),
    userId: () async => user,
    ids: RandomIdGenerator(),
    enabled: true,
    config: const SyncEngineConfig(),
    sleep: (d) async {},
  );
  return _Node(file, db, repo, outbox, state, engine);
}

Future<String> _newUser() async {
  final id = _id();
  await mustPsql(_database, "insert into auth.users(id) values ('$id');");
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

/// An older client talking to the migrated server: it knows no `due_time`, so its
/// patches never mention it, and it ignores the field in every answer.
Future<List<Object?>> _oldClientPush(
  PsqlTransport t,
  String device,
  List<Map<String, Object?>> ops,
) => t.push(device, ops);

Future<(_Node, _Node, String, String, String)> _pair() async {
  final user = await _newUser();
  final a = _node(_transport(user), user);
  final b = _node(_transport(user), user);
  final p = _id();
  await a.engine.syncNow(); // learns what the server understands
  await b.engine.syncNow();
  await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
  return (a, b, user, p, _id());
}

void main() {
  setUpAll(() async {
    if (e2eEnabled) {
      _database = await createE2eDatabase();
    }
  });
  tearDownAll(() async {
    if (e2eEnabled) {
      await dropE2eDatabase(_database);
    }
  });
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-due-'));
  tearDown(() => _dir.deleteSync(recursive: true));
  final skip = e2eEnabled
      ? null
      : 'set NEXORA_E2E_PG=1 with a PostgreSQL server';

  test('the client learns that the server stores due times', () async {
    final user = await _newUser();
    final a = _node(_transport(user), user);
    expect(
      a.state.serverSupportsDueTime,
      isFalse,
      reason: 'unknown until asked',
    );
    await a.engine.syncNow();
    expect(a.state.serverFeatures, contains('due_time'));
    expect(a.state.serverSupportsDueTime, isTrue);
  }, skip: skip);

  test('create with a time, receive it, edit it, clear it: the date stays', () async {
    final (a, b, user, p, t) = await _pair();
    await a.repo.saveTask(
      makeTask(
        id: t,
        projectId: p,
        title: 'T',
        dueDate: _d1,
        dueTime: const DueTime(17, 30),
      ),
    );
    await _converge([a, b]);
    expect(
      await _q(
        "select due_date||' '||due_time from public.tasks where id='$t'",
      ),
      '2026-11-20 17:30:00',
    );
    expect(await b.dateTime(t), (_d1, const DueTime(17, 30)));
    expect(b.task(t)['due_time'], '17:30'); // normalized: no seconds

    await b.repo.saveTask(
      (await b.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueTime: const DueTime(8, 5)),
    );
    await _converge([a, b]);
    expect(await a.dateTime(t), (_d1, const DueTime(8, 5)));

    await a.repo.saveTask(
      (await a.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(clearDueTime: true),
    );
    await _converge([a, b]);
    expect(await b.dateTime(t), (_d1, null)); // time cleared, date kept
    expect(
      await _q(
        "select due_date||'|'||coalesce(due_time::text,'NULL') from public.tasks where id='$t'",
      ),
      '2026-11-20|NULL',
    );
    expect(user, isNotEmpty);
  }, skip: skip);

  test('a date-only task stays date-only on both sides (no invented time)', () async {
    final (a, b, user, p, t) = await _pair();
    await a.repo.saveTask(
      makeTask(id: t, projectId: p, title: 'D', dueDate: _d1),
    );
    expect(a.pendingPatches().last.contains('due_time'), isFalse);
    await _converge([a, b]);
    expect(await b.dateTime(t), (_d1, null));
    expect(
      await _q(
        "select coalesce(due_time::text,'NULL') from public.tasks where id='$t'",
      ),
      'NULL',
    );
    // moving the date of a date-only task never adds a time
    await b.repo.saveTask(
      (await b.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueDate: _d2),
    );
    expect(b.pendingPatches().last.contains('due_time'), isFalse);
    await _converge([a, b]);
    expect(await a.dateTime(t), (_d2, null));
    expect(user, isNotEmpty);
  }, skip: skip);

  test('moving the date keeps the time (sent together); clearing the date clears both', () async {
    final (a, b, _, p, t) = await _pair();
    await a.repo.saveTask(
      makeTask(
        id: t,
        projectId: p,
        title: 'T',
        dueDate: _d1,
        dueTime: const DueTime(9, 0),
      ),
    );
    await _converge([a, b]);
    await a.repo.saveTask(
      (await a.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueDate: _d2),
    );
    // the patch carries the date AND the unchanged time
    final patch = a.pendingPatches().last;
    expect(patch, contains('due_date'));
    expect(patch, contains('"due_time":"09:00"'));
    await _converge([a, b]);
    expect(await b.dateTime(t), (_d2, const DueTime(9, 0)));

    await b.repo.saveTask(
      (await b.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(clearDueDate: true),
    );
    await _converge([a, b]);
    expect(await a.dateTime(t), (null, null));
    expect(
      await _q(
        "select coalesce(due_date::text,'N')||'|'||coalesce(due_time::text,'N') from public.tasks where id='$t'",
      ),
      'N|N',
    );
  }, skip: skip);

  test('offline edits are retried, folded, survive a restart and then arrive', () async {
    final (a, b, user, p, t) = await _pair();
    await a.repo.saveTask(
      makeTask(id: t, projectId: p, title: 'T', dueDate: _d1),
    );
    await _converge([a, b]);
    // offline: three edits of the time fold into one pending operation
    await a.repo.saveTask(
      (await a.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueTime: const DueTime(10, 0)),
    );
    await a.repo.saveTask(
      (await a.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueTime: const DueTime(11, 0)),
    );
    await a.repo.saveTask(
      (await a.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueTime: const DueTime(12, 15)),
    );
    expect(a.pendingPatches(), hasLength(1));
    // a failing network keeps the operation
    final offline = _node(_FailingTransport(), user, path: a.path);
    a.db.close();
    expect((await offline.engine.syncNow()).phase, isNot(SyncPhase.idle));
    expect(offline.pendingPatches(), hasLength(1));
    // restart: reopen the same file with a working network
    final restarted = _node(_transport(user), user, path: a.path);
    expect(await restarted.dateTime(t), (_d1, const DueTime(12, 15)));
    await _converge([restarted, b]);
    expect(await b.dateTime(t), (_d1, const DueTime(12, 15)));
    expect(
      await _q(
        "select count(*) from public.sync_operations where user_id='$user' and status='rejected'",
      ),
      '0',
    );
  }, skip: skip);

  group('concurrent edits and conflicts', () {
    Future<(_Node, _Node, String, String, String, String)> timed() async {
      final (a, b, user, p, t) = await _pair();
      await a.repo.saveTask(
        makeTask(
          id: t,
          projectId: p,
          title: 'T',
          dueDate: _d1,
          dueTime: const DueTime(10, 0),
        ),
      );
      await _converge([a, b]);
      return (a, b, user, p, t, user);
    }

    Future<String> conflictOf(_Node n, String t) async =>
        n.outbox.conflictsNeedingAction().firstWhere(
              (c) => c['entity_id'] == t,
            )['id']!
            as String;

    Future<void> edit(_Node n, String t, DueTime time) async => n.repo.saveTask(
      (await n.repo.loadTasks())
          .firstWhere((x) => x.id == t)
          .copyWith(dueTime: time),
    );

    test('the same time edited on two devices is a conflict on due_time; keep mine', () async {
      final (a, b, _, _, t, _) = await timed();
      await edit(a, t, const DueTime(11, 0));
      await edit(b, t, const DueTime(12, 0));
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(b.engine.status.openConflicts, 1);
      expect(
        await _q(
          "select fields::text from public.sync_conflicts where entity_id='$t'",
        ),
        contains('due_time'),
      );
      // the screen shows readable values
      final view = ConflictService(
        outbox: b.outbox,
        db: b.db,
        engine: () => b.engine,
      ).list().single;
      final time = view.fields.firstWhere((f) => f.field == 'due_time');
      expect(time.label, 'Due time');
      expect(time.server.text, '11:00');
      expect(time.local.text, '12:00');
      await b.engine.resolveConflict(
        await conflictOf(b, t),
        ConflictChoice.keepLocal,
      );
      await _converge([a, b]);
      expect(await a.dateTime(t), (_d1, const DueTime(12, 0)));
      expect(await b.dateTime(t), (_d1, const DueTime(12, 0)));
    }, skip: skip);

    test('use the server version', () async {
      final (a, b, _, _, t, _) = await timed();
      await edit(a, t, const DueTime(11, 0));
      await edit(b, t, const DueTime(12, 0));
      await a.engine.syncNow();
      await b.engine.syncNow();
      await b.engine.resolveConflict(
        await conflictOf(b, t),
        ConflictChoice.useServer,
      );
      await _converge([a, b]);
      expect(await b.dateTime(t), (_d1, const DueTime(11, 0)));
    }, skip: skip);

    test(
      'merge: the picked time goes through the wire in its HH:MM form',
      () async {
        final (a, b, _, _, t, _) = await timed();
        Future<void> both(_Node n, String title, DueTime time) async =>
            n.repo.saveTask(
              (await n.repo.loadTasks())
                  .firstWhere((x) => x.id == t)
                  .copyWith(title: title, dueTime: time),
            );
        await both(a, 'A title', const DueTime(11, 0));
        await both(b, 'B title', const DueTime(12, 0));
        await a.engine.syncNow();
        await b.engine.syncNow();
        final id = await conflictOf(b, t);
        final service = ConflictService(
          outbox: b.outbox,
          db: b.db,
          engine: () => b.engine,
        );
        expect(service.list().single.choices, contains(ConflictChoice.merge));
        // The SERVER time is picked: PostgreSQL stores 11:00:00, the wire form is 11:00.
        final outcome = await service.resolve(
          id,
          ConflictChoice.merge,
          picks: {'due_time': MergePick.server, 'title': MergePick.local},
        );
        expect(
          outcome.ok,
          isTrue,
          reason: 'kind=${outcome.kind} code=${outcome.code}',
        );
        await _converge([a, b]);
        for (final n in [a, b]) {
          final task = (await n.repo.loadTasks()).firstWhere((x) => x.id == t);
          expect(task.title, 'B title');
          expect(task.dueTime, const DueTime(11, 0));
        }
      },
      skip: skip,
    );

    test('one device moves the date (keeping the time), the other changes the time: both survive', () async {
      final (a, b, _, _, t, user) = await timed();
      await a.repo.saveTask(
        (await a.repo.loadTasks())
            .firstWhere((x) => x.id == t)
            .copyWith(dueDate: _d2),
      );
      await edit(b, t, const DueTime(18, 45));
      await _converge([a, b]);
      for (final n in [a, b]) {
        expect(await n.dateTime(t), (_d2, const DueTime(18, 45)));
      }
      expect(
        await _q(
          "select count(*) from public.sync_conflicts where user_id = '$user'",
        ),
        '0',
      );
    }, skip: skip);

    test('an edit of a task that was deleted elsewhere is recreated as a copy with its time', () async {
      final (a, b, _, _, t, user) = await timed();
      await a.repo.softDeleteTask(t);
      await edit(b, t, const DueTime(20, 0));
      await a.engine.syncNow();
      await b.engine.syncNow();
      await b.engine.resolveConflict(
        await conflictOf(b, t),
        ConflictChoice.recreateCopy,
      );
      await _converge([a, b]);
      final copy = await _q(
        "select due_date||' '||due_time from public.tasks where owner_id = '$user' and deleted_at is null and title='T'",
      );
      expect(copy, '2026-11-20 20:00:00');
    }, skip: skip);
  });

  group('an older client (no due_time in its patches)', () {
    test('changing the date clears the stored time on the server and on every new client', () async {
      final (a, b, user, p, t) = await _pair();
      await a.repo.saveTask(
        makeTask(
          id: t,
          projectId: p,
          title: 'T',
          dueDate: _d1,
          dueTime: const DueTime(14, 0),
        ),
      );
      await _converge([a, b]);
      final device = _id();
      final old = _transport(user);
      await old.registerDevice(device);
      final res = await _oldClientPush(old, device, [
        {
          'operation_id': _id(),
          'entity_type': 'task',
          'entity_id': t,
          'op_type': 'update',
          'base_version': int.parse(
            await _q("select version from public.tasks where id='$t'"),
          ),
          'patch': {'due_date': '2026-12-24'},
        },
      ]);
      expect((res.single! as Map)['status'], 'applied');
      expect(
        await _q(
          "select due_date||'|'||coalesce(due_time::text,'N') from public.tasks where id='$t'",
        ),
        '2026-12-24|N',
      );
      await _converge([a, b]);
      for (final n in [a, b]) {
        expect(await n.dateTime(t), (
          const CalendarDate(2026, 12, 24),
          null,
        ), reason: 'no stale 14:00 survives');
      }
    }, skip: skip);

    test(
      'clearing the date clears the time (no constraint failure, no rejection)',
      () async {
        final (a, b, user, p, t) = await _pair();
        await a.repo.saveTask(
          makeTask(
            id: t,
            projectId: p,
            title: 'T',
            dueDate: _d1,
            dueTime: const DueTime(14, 0),
          ),
        );
        await _converge([a, b]);
        final device = _id();
        final old = _transport(user);
        await old.registerDevice(device);
        final res = await _oldClientPush(old, device, [
          {
            'operation_id': _id(),
            'entity_type': 'task',
            'entity_id': t,
            'op_type': 'update',
            'base_version': int.parse(
              await _q("select version from public.tasks where id='$t'"),
            ),
            'patch': {'due_date': null},
          },
        ]);
        expect((res.single! as Map)['status'], 'applied');
        await _converge([a, b]);
        expect(await b.dateTime(t), (null, null));
      },
      skip: skip,
    );

    test('its reads of a task with a time are unaffected: the extra key is ignored', () async {
      final (a, _, user, p, t) = await _pair();
      await a.repo.saveTask(
        makeTask(
          id: t,
          projectId: p,
          title: 'T',
          dueDate: _d1,
          dueTime: const DueTime(14, 0),
        ),
      );
      await a.engine.syncNow();
      final device = _id();
      await _transport(user).registerDevice(device);
      final pull = await _transport(user).pull(device, 0);
      final row =
          ((pull['changes']! as List).whereType<Map>().firstWhere(
                (c) => (c['row'] as Map)['id'] == t,
              ))['row']
              as Map;
      expect(
        row['due_date'],
        '2026-11-20',
      ); // still a plain date for an old reader
      expect(row.containsKey('due_time'), isTrue);
    }, skip: skip);
  });

  group('a server without the migration', () {
    test(
      'no features: the time is not used, a date-only task still syncs',
      () async {
        final user = await _newUser();
        final a = _node(_OldServer(_transport(user)), user);
        final p = _id(), t = _id();
        await a.engine.syncNow();
        expect(a.state.serverSupportsDueTime, isFalse);
        await a.repo.saveProject(Project(id: p, name: 'Home', position: 0));
        await a.repo.saveTask(
          makeTask(id: t, projectId: p, title: 'T', dueDate: _d1),
        );
        expect((await a.engine.syncNow()).phase, SyncPhase.idle);
        // a new time on a synchronized task is refused instead of staying on this device only
        await expectLater(
          a.repo.saveTask(
            makeTask(
              id: t,
              projectId: p,
              title: 'T',
              dueDate: _d1,
              dueTime: const DueTime(9, 0),
            ),
          ),
          throwsA(isA<RepositoryException>()),
        );
        expect((await a.dateTime(t)).$2, isNull);
      },
      skip: skip,
    );

    test(
      'a feature that disappears (rollback) is noticed at the next start',
      () async {
        final user = await _newUser();
        final a = _node(_transport(user), user);
        await a.engine.syncNow();
        expect(a.state.serverSupportsDueTime, isTrue);
        final again = _node(_OldServer(_transport(user)), user, path: a.path);
        a.db.close();
        await again.engine.syncNow();
        expect(again.state.serverSupportsDueTime, isFalse);
      },
      skip: skip,
    );
  });

  group('local-to-account import', () {
    Future<(_Node, String, String)> localWithTimes() async {
      final src = LocalDatabase.open(
        '${_dir.path}${Platform.pathSeparator}local-src.db',
      );
      addTearDown(src.close);
      final repo = SqliteTaskRepository(src, ownerId: 'local');
      final p = _id();
      await repo.saveProject(
        Project(id: p, name: 'Local project', position: 0),
      );
      // a "synchronized-class" local record is needed: a fresh local database classifies new records as synced
      await repo.saveTask(
        makeTask(
          id: _id(),
          projectId: p,
          title: 'Timed',
          dueDate: _d1,
          dueTime: const DueTime(15, 45),
        ),
      );
      await repo.saveTask(
        makeTask(id: _id(), projectId: p, title: 'Date only', dueDate: _d1),
      );
      final user = await _newUser();
      final acc = _node(_transport(user), user);
      return (acc, '${_dir.path}${Platform.pathSeparator}local-src.db', user);
    }

    test('with a migrated server the preview says times are kept and the import keeps them', () async {
      final (acc, src, _) = await localWithTimes();
      await acc.engine.syncNow();
      final service = LocalImportService(
        sourcePath: src,
        target: acc.db,
        repository: acc.repo,
        ids: RandomIdGenerator(),
        dueTimeSupported: () => acc.state.serverSupportsDueTime,
      );
      final preview = await service.preview();
      expect(preview.dueTimesTransferable, isTrue);
      expect(preview.candidates.single.dueTimeCount, 1);
      await service.run([
        ImportChoice(sourceProjectId: preview.candidates.single.project.id),
      ]);
      final tasks = await acc.repo.loadTasks();
      expect(
        tasks.firstWhere((t) => t.title == 'Timed').dueTime,
        const DueTime(15, 45),
      );
      expect(tasks.firstWhere((t) => t.title == 'Date only').dueTime, isNull);
      expect((await acc.engine.syncNow()).phase, SyncPhase.idle);
      expect(
        await _q("select due_time::text from public.tasks where title='Timed'"),
        '15:45:00',
      );
    }, skip: skip);

    test('without server support the preview warns and the import drops the time, keeping the date', () async {
      final (acc, src, user) = await localWithTimes();
      final old = _node(_OldServer(_transport(user)), user, path: acc.path);
      acc.db.close();
      await old.engine.syncNow();
      final service = LocalImportService(
        sourcePath: src,
        target: old.db,
        repository: old.repo,
        ids: RandomIdGenerator(),
        dueTimeSupported: () => old.state.serverSupportsDueTime,
      );
      final preview = await service.preview();
      expect(preview.dueTimesTransferable, isFalse);
      expect(preview.candidates.single.dueTimeCount, 1);
      await service.run([
        ImportChoice(sourceProjectId: preview.candidates.single.project.id),
      ]);
      final timed = (await old.repo.loadTasks()).firstWhere(
        (t) => t.title == 'Timed',
      );
      expect(timed.dueDate, _d1);
      expect(timed.dueTime, isNull);
    }, skip: skip);
  });
}

/// A network that never answers.
final class _FailingTransport implements SyncTransport {
  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) => throw const SyncNetworkFailure('offline');
  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) => throw const SyncNetworkFailure('offline');
  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) => throw const SyncNetworkFailure('offline');
  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) => throw const SyncNetworkFailure('offline');
  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) => throw const SyncNetworkFailure('offline');
}

/// The migrated server as an older server would answer registration: no `features`.
final class _OldServer implements SyncTransport {
  _OldServer(this.inner);
  final SyncTransport inner;
  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) async {
    final answer = Map<String, Object?>.from(
      await inner.registerDevice(deviceId, label: label),
    );
    answer.remove('features');
    return answer;
  }

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) => inner.push(deviceId, operations);
  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) => inner.pull(deviceId, cursor, limit: limit);
  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) => inner.resolveConflict(
    deviceId: deviceId,
    operationId: operationId,
    conflictId: conflictId,
    resolution: resolution,
    values: values,
  );
  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) => inner.revokeDevice(deviceId, targetDeviceId);
}
