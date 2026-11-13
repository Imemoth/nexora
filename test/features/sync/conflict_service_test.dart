import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/sync/conflicts.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/pull_applier.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';

import '../../support/fake_sync_server.dart';
import '../../support/sequential_id_generator.dart';
import '../../support/task_fixtures.dart';

/// The conflict screens' logic over the real engine and a fake server:
/// what is listed, which decisions are valid, what each one does, and what a
/// failure leaves behind.
late Directory _dir;
var _files = 0;

DateTime _clock() => DateTime.utc(2026, 11, 12, 10);

final class _Node {
  _Node(this.path, this.db, this.repo, this.outbox, this.state, this.engine) {
    service = ConflictService(outbox: outbox, db: db, engine: () => engine);
  }

  final String path;
  final LocalDatabase db;
  final SqliteTaskRepository repo;
  final OutboxStore outbox;
  final SyncStateStore state;
  final SyncEngine engine;
  late final ConflictService service;

  Map<String, Object?> task(String id) => {
    for (final e
        in db.raw
            .select('SELECT * FROM tasks WHERE id = ?', [id])
            .single
            .entries)
      e.key: e.value,
  };
}

/// [path] reopens an existing file (a restart); [name] keeps ids unique.
_Node _node(String name, SyncTransport transport, {String? path}) {
  _files++;
  final file = path ?? '${_dir.path}${Platform.pathSeparator}$name-$_files.db';
  final db = LocalDatabase.open(file);
  addTearDown(() {
    try {
      db.close();
    } on Object {
      // closed by the test
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
  final engine = SyncEngine(
    transport: transport,
    outbox: outbox,
    state: state,
    pull: PullApplier(db, now: _clock),
    userId: () async => 'user-1',
    ids: SequentialIdGenerator(ids('e')),
    enabled: true,
    sleep: (d) async {},
  );
  return _Node(file, db, repo, outbox, state, engine);
}

Future<void> _seed(_Node n) async {
  await n.repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
  await n.repo.saveTask(
    makeTask(id: 't1', projectId: 'p1', title: 'Original', notes: 'n0'),
  );
  await n.repo.saveTask(
    makeTask(id: 't2', projectId: 'p1', title: 'Second', notes: 'm0'),
  );
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-conf-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  /// Two devices on one server; both have the seeded tasks synchronized.
  Future<(FakeSyncServer, FaultyTransport, _Node, _Node)> twoDevices() async {
    final server = FakeSyncServer();
    final faulty = FaultyTransport(server);
    final a = _node('a', server);
    final b = _node('b', faulty);
    await _seed(a);
    await a.engine.syncNow();
    await b.engine.syncNow();
    return (server, faulty, a, b);
  }

  /// Device A and B change the title of t1 differently; B ends with the conflict.
  Future<void> titleConflict(_Node a, _Node b, {String id = 't1'}) async {
    await a.repo.saveTask(
      makeTask(
        id: id,
        projectId: 'p1',
        title: 'CONFLICT-A',
        notes: id == 't1' ? 'n0' : 'm0',
      ),
    );
    await b.repo.saveTask(
      makeTask(
        id: id,
        projectId: 'p1',
        title: 'CONFLICT-B',
        notes: id == 't1' ? 'n0' : 'm0',
      ),
    );
    await a.engine.syncNow();
    await b.engine.syncNow();
  }

  group('listing and comparison', () {
    test(
      'a field conflict is shown with both values, names and the valid choices',
      () async {
        final (_, _, a, b) = await twoDevices();
        await titleConflict(a, b);

        final view = b.service.list().single;
        expect(view.entityName, 'CONFLICT-B'); // the local version's title
        expect(view.projectName, 'Home');
        expect(view.kind, 'field');
        expect(view.status, ConflictStatus.open);
        final title = view.fields.single;
        expect(title.label, 'Title');
        expect(title.local, const ConflictSide.value('CONFLICT-B'));
        expect(title.server, const ConflictSide.value('CONFLICT-A'));
        expect(title.differs, isTrue);
        // one differing field: no merge; a deletion strategy would be invalid
        expect(view.choices, {
          ConflictChoice.useServer,
          ConflictChoice.keepLocal,
        });
      },
    );

    test(
      'several fields: each is compared, readable values, merge is offered',
      () async {
        final (_, _, a, b) = await twoDevices();
        await a.repo.saveTask(
          makeTask(
            id: 't1',
            projectId: 'p1',
            title: 'Same title',
            notes: 'server notes',
            priority: TaskPriority.high,
          ),
        );
        await b.repo.saveTask(
          makeTask(
            id: 't1',
            projectId: 'p1',
            title: 'Same title',
            notes: 'my notes',
            priority: TaskPriority.low,
          ),
        );
        await a.engine.syncNow();
        await b.engine.syncNow();

        final view = b.service.list().single;
        final byLabel = {for (final f in view.fields) f.label: f};
        expect(byLabel.keys, containsAll(['Notes', 'Priority']));
        expect(byLabel['Priority']!.local, const ConflictSide.value('Low'));
        expect(byLabel['Priority']!.server, const ConflictSide.value('High'));
        expect(byLabel['Notes']!.differs, isTrue);
        expect(view.choices, contains(ConflictChoice.merge));
        expect(view.mergeFields, hasLength(2));
      },
    );

    test(
      'a deletion conflict says deleted instead of inventing a value',
      () async {
        final (_, _, a, b) = await twoDevices();
        await a.repo.softDeleteTask('t2');
        await b.repo.saveTask(
          makeTask(
            id: 't2',
            projectId: 'p1',
            title: 'Edited here',
            notes: 'm0',
          ),
        );
        await a.engine.syncNow();
        await b.engine.syncNow();

        final view = b.service.list().single;
        expect(view.kind, 'edit_deleted');
        expect(view.fields.first.server, const ConflictSide.deleted());
        expect(
          view.fields.first.local,
          const ConflictSide.value('Changed by you'),
        );
        expect(view.choices, {
          ConflictChoice.useServer,
          ConflictChoice.recreateCopy,
        });
      },
    );

    test('several unresolved conflicts are all listed, oldest first', () async {
      final (_, _, a, b) = await twoDevices();
      await titleConflict(a, b, id: 't1');
      await a.repo.saveTask(
        makeTask(id: 't2', projectId: 'p1', title: 'A2', notes: 'm0'),
      );
      await b.repo.saveTask(
        makeTask(id: 't2', projectId: 'p1', title: 'B2', notes: 'm0'),
      );
      await a.engine.syncNow();
      await b.engine.syncNow();

      final views = b.service.list();
      expect(views.map((v) => v.entityName), ['CONFLICT-B', 'B2']);
      expect(b.engine.status.openConflicts, 2);
    });
  });

  group('every strategy', () {
    test('use server: the device takes the server value and the conflict leaves the list', () async {
      final (server, _, a, b) = await twoDevices();
      await titleConflict(a, b);
      final id = b.service.list().single.id;

      final outcome = await b.service.resolve(id, ConflictChoice.useServer);

      expect(outcome.ok, isTrue);
      expect(b.task('t1')['title'], 'CONFLICT-A');
      expect(b.service.list(), isEmpty);
      expect(b.engine.status.openConflicts, 0);
      expect(server.conflicts.values.single['status'], 'resolved_server');
    });

    test('keep local: both devices converge on the local value', () async {
      final (server, _, a, b) = await twoDevices();
      await titleConflict(a, b);
      final id = b.service.list().single.id;

      final outcome = await b.service.resolve(id, ConflictChoice.keepLocal);
      await b.engine.syncNow();
      await a.engine.syncNow();

      expect(outcome.ok, isTrue);
      expect(server.rows['task:t1']!['title'], 'CONFLICT-B');
      expect(a.task('t1')['title'], 'CONFLICT-B');
      expect(b.task('t1')['title'], 'CONFLICT-B');
      expect(b.service.list(), isEmpty);
    });

    test(
      'merge: the picked side of every field is applied everywhere',
      () async {
        final (server, _, a, b) = await twoDevices();
        await a.repo.saveTask(
          makeTask(
            id: 't1',
            projectId: 'p1',
            title: 'A title',
            notes: 'A notes',
          ),
        );
        await b.repo.saveTask(
          makeTask(
            id: 't1',
            projectId: 'p1',
            title: 'B title',
            notes: 'B notes',
          ),
        );
        await a.engine.syncNow();
        await b.engine.syncNow();
        final view = b.service.list().single;

        final outcome = await b.service.resolve(
          view.id,
          ConflictChoice.merge,
          picks: {'title': MergePick.local, 'notes': MergePick.server},
        );
        await b.engine.syncNow();
        await a.engine.syncNow();

        expect(outcome.ok, isTrue);
        expect(server.rows['task:t1']!['title'], 'B title');
        expect(server.rows['task:t1']!['notes'], 'A notes');
        expect(a.task('t1')['title'], 'B title');
        expect(b.task('t1')['notes'], 'A notes');
      },
    );

    test('recreate as copy: the deleted item stays deleted and the copy holds the local values', () async {
      final (server, _, a, b) = await twoDevices();
      await a.repo.softDeleteTask('t2');
      await b.repo.saveTask(
        makeTask(id: 't2', projectId: 'p1', title: 'Edited here', notes: 'm0'),
      );
      await a.engine.syncNow();
      await b.engine.syncNow();
      final id = b.service.list().single.id;

      final outcome = await b.service.resolve(id, ConflictChoice.recreateCopy);
      await b.engine.syncNow();
      await a.engine.syncNow();

      expect(outcome.ok, isTrue);
      expect(server.rows['task:t2']!['deleted_at'], isNotNull);
      final copies = server.rows.values.where(
        (r) => r['title'] == 'Edited here' && r['deleted_at'] == null,
      );
      expect(copies, hasLength(1));
      expect(b.service.list(), isEmpty);
    });

    test(
      'delete edited elsewhere: keep the item, or delete it anyway',
      () async {
        // keep the item (use server)
        var (server, _, a, b) = await twoDevices();
        await a.repo.saveTask(
          makeTask(
            id: 't2',
            projectId: 'p1',
            title: 'Changed on A',
            notes: 'm0',
          ),
        );
        await b.repo.softDeleteTask('t2');
        await a.engine.syncNow();
        await b.engine.syncNow();
        var view = b.service.list().single;
        expect(view.kind, 'delete_edited');
        expect(view.choices, {
          ConflictChoice.useServer,
          ConflictChoice.keepLocal,
        });
        expect(
          (await b.service.resolve(view.id, ConflictChoice.useServer)).ok,
          isTrue,
        );
        expect(b.task('t2')['deleted_at'], isNull);
        expect(server.rows['task:t2']!['deleted_at'], isNull);

        // delete anyway (keep local)
        _dir.deleteSync(recursive: true);
        _dir.createSync();
        (server, _, a, b) = await twoDevices();
        await a.repo.saveTask(
          makeTask(
            id: 't2',
            projectId: 'p1',
            title: 'Changed on A',
            notes: 'm0',
          ),
        );
        await b.repo.softDeleteTask('t2');
        await a.engine.syncNow();
        await b.engine.syncNow();
        view = b.service.list().single;
        expect(
          (await b.service.resolve(view.id, ConflictChoice.keepLocal)).ok,
          isTrue,
        );
        await b.engine.syncNow();
        expect(server.rows['task:t2']!['deleted_at'], isNotNull);
      },
    );
  });

  group('invalid, duplicate and unknown decisions', () {
    test('a strategy that is not valid for the conflict is refused and nothing is sent', () async {
      final (server, _, a, b) = await twoDevices();
      await titleConflict(a, b);
      final id = b.service.list().single.id;
      final before = server.log.where((l) => l.startsWith('resolve')).length;

      for (final choice in [
        ConflictChoice.recreateCopy,
        ConflictChoice.merge,
      ]) {
        final outcome = await b.service.resolve(id, choice);
        expect(outcome.kind, ConflictOutcomeKind.unsupported);
      }
      expect(server.log.where((l) => l.startsWith('resolve')).length, before);
      expect(b.service.list(), hasLength(1)); // untouched
    });

    test('a merge without a pick for every field is refused', () async {
      final (_, _, a, b) = await twoDevices();
      await a.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'A', notes: 'A notes'),
      );
      await b.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'B', notes: 'B notes'),
      );
      await a.engine.syncNow();
      await b.engine.syncNow();
      final id = b.service.list().single.id;

      final outcome = await b.service.resolve(
        id,
        ConflictChoice.merge,
        picks: {'title': MergePick.local},
      );

      expect(outcome.kind, ConflictOutcomeKind.unsupported);
    });

    test('an unknown conflict id is reported, not thrown', () async {
      final (_, _, _, b) = await twoDevices();
      final outcome = await b.service.resolve('nope', ConflictChoice.useServer);
      expect(outcome.kind, ConflictOutcomeKind.notFound);
    });

    test(
      'a second click while the decision is in flight is not sent twice',
      () async {
        final (server, faulty, a, b) = await twoDevices();
        await titleConflict(a, b);
        final id = b.service.list().single.id;
        final gate = Completer<void>();
        faulty.before = (call) async {
          if (call == 'resolve') await gate.future;
        };

        final first = b.service.resolve(id, ConflictChoice.keepLocal);
        await Future<void>.delayed(Duration.zero);
        expect(b.service.isResolving(id), isTrue);
        final second = await b.service.resolve(id, ConflictChoice.keepLocal);
        expect(second.kind, ConflictOutcomeKind.inProgress);
        gate.complete();

        expect((await first).ok, isTrue);
        expect(server.log.where((l) => l.startsWith('resolve')), hasLength(1));
        // and after completion the conflict is simply gone
        expect(
          (await b.service.resolve(id, ConflictChoice.keepLocal)).kind,
          ConflictOutcomeKind.notFound,
        );
      },
    );
  });

  group('failures keep everything', () {
    test(
      'offline: nothing changes, the evidence stays, a retry works',
      () async {
        final (server, faulty, a, b) = await twoDevices();
        await titleConflict(a, b);
        final id = b.service.list().single.id;
        final pendingBefore = b.state.counts();
        var fail = true;
        faulty.before = (call) async {
          if (call == 'resolve' && fail) {
            throw const SyncNetworkFailure('offline');
          }
        };

        final outcome = await b.service.resolve(id, ConflictChoice.keepLocal);

        expect(outcome.kind, ConflictOutcomeKind.offline);
        expect(b.task('t1')['title'], 'CONFLICT-B'); // local data untouched
        expect(b.service.list().single.id, id); // still listed
        expect(b.state.counts().openConflicts, pendingBefore.openConflicts);
        expect(server.conflicts.values.single['status'], 'open');

        fail = false;
        expect(
          (await b.service.resolve(id, ConflictChoice.keepLocal)).ok,
          isTrue,
        );
        expect(b.service.list(), isEmpty);
      },
    );

    test(
      'expired authentication and a revoked device are reported separately',
      () async {
        final (server, faulty, a, b) = await twoDevices();
        await titleConflict(a, b);
        final id = b.service.list().single.id;

        faulty.before = (call) async {
          if (call == 'resolve') throw const SyncAuthFailure('expired');
        };
        expect(
          (await b.service.resolve(id, ConflictChoice.useServer)).kind,
          ConflictOutcomeKind.authRequired,
        );

        faulty.before = (call) async {
          if (call == 'resolve') throw const SyncServerError('device_invalid');
        };
        expect(
          (await b.service.resolve(id, ConflictChoice.useServer)).kind,
          ConflictOutcomeKind.deviceRevoked,
        );
        expect(server.conflicts.values.single['status'], 'open');
        expect(b.service.list(), hasLength(1));
        expect(b.task('t1')['title'], 'CONFLICT-B');
      },
    );

    test('a server rejection is explained and changes nothing', () async {
      final (_, faulty, a, b) = await twoDevices();
      await titleConflict(a, b);
      final id = b.service.list().single.id;
      faulty.before = (call) async {
        if (call == 'resolve') {
          throw const SyncServerError('strategy_not_allowed');
        }
      };

      final outcome = await b.service.resolve(id, ConflictChoice.keepLocal);

      expect(outcome.kind, ConflictOutcomeKind.rejected);
      expect(outcome.code, 'strategy_not_allowed');
      expect(b.service.list(), hasLength(1));
    });

    test(
      'no engine (signed out): authentication is required, nothing changes',
      () async {
        final (_, _, a, b) = await twoDevices();
        await titleConflict(a, b);
        final id = b.service.list().single.id;
        final detached = ConflictService(
          outbox: b.outbox,
          db: b.db,
          engine: () => null,
        );

        final outcome = await detached.resolve(id, ConflictChoice.useServer);

        expect(outcome.kind, ConflictOutcomeKind.authRequired);
        expect(detached.list(), hasLength(1));
      },
    );

    test('already decided on another device: this device applies the outcome locally', () async {
      final (server, _, a, b) = await twoDevices();
      await titleConflict(a, b);
      final id = b.service.list().single.id;
      // Another device of the account decides on the server first.
      final other = await server.resolveConflict(
        deviceId: b.outbox.deviceId(),
        operationId: 'other-device-op',
        conflictId: id,
        resolution: 'resolved_server',
      );
      expect(other['status'], 'applied');

      // The server now says the conflict is not open.
      final outcome = await b.service.resolve(id, ConflictChoice.keepLocal);
      expect(outcome.kind, ConflictOutcomeKind.alreadyDecidedElsewhere);
      expect(b.service.list(), hasLength(1)); // still waiting locally

      // After synchronizing, the conflict is shown as decided elsewhere.
      await b.engine.syncNow();
      final view = b.service.list().single;
      expect(view.status, ConflictStatus.decidedElsewhere);
      expect(view.choices, {
        ConflictChoice.useServer,
        ConflictChoice.keepLocal,
      });

      // Applying the server's decision here needs no server call.
      int resolves() => server.log.where((l) => l.startsWith('resolve')).length;
      final before = resolves();
      expect(
        (await b.service.resolve(id, ConflictChoice.useServer)).ok,
        isTrue,
      );
      expect(resolves(), before);
      expect(b.task('t1')['title'], 'CONFLICT-A');
      expect(b.service.list(), isEmpty);
    });
  });

  group('restart', () {
    test('the conflict and its evidence survive a restart; a retried decision is applied once', () async {
      final (server, faulty, a, b) = await twoDevices();
      await titleConflict(a, b);
      final id = b.service.list().single.id;
      // The network drops while the decision is sent, then the app ends.
      var lose = true;
      faulty.before = (call) async {
        if (call == 'resolve' && lose) throw const SyncNetworkFailure('lost');
      };
      expect(
        (await b.service.resolve(id, ConflictChoice.keepLocal)).kind,
        ConflictOutcomeKind.offline,
      );
      final path = b.path;
      b.db.close();

      final restarted = _node('b2', faulty, path: path);
      lose = false;
      final view = restarted.service.list().single; // evidence persisted
      expect(view.id, id);
      expect(view.fields.single.local, const ConflictSide.value('CONFLICT-B'));
      expect(view.fields.single.server, const ConflictSide.value('CONFLICT-A'));

      expect(
        (await restarted.service.resolve(id, ConflictChoice.keepLocal)).ok,
        isTrue,
      );
      expect(server.rows['task:t1']!['title'], 'CONFLICT-B');
      expect(restarted.service.list(), isEmpty);
    });
  });
}
