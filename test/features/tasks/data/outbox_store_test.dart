import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/sequential_id_generator.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/v1_database.dart';

/// S5: the outbox state machine, rule R, acknowledgement handling, conflict
/// mirror, recovery actions, and the repository behaviors built on them.
late Directory _dir;
var _n = 0;

String _path() {
  _n++;
  return '${_dir.path}${Platform.pathSeparator}o-$_n.db';
}

SequentialIdGenerator _ids() {
  return SequentialIdGenerator([for (var i = 0; i < 2000; i++) 'id-$i']);
}

DateTime _clock() => DateTime.utc(2026, 11, 12, 10);

final class _Env {
  _Env(this.db, this.repo, this.store);

  final LocalDatabase db;
  final SqliteTaskRepository repo;
  final OutboxStore store;

  List<Map<String, Object?>> ops([String where = '1 = 1']) =>
      _rows(db.raw, 'SELECT * FROM sync_outbox WHERE $where ORDER BY seq');

  Map<String, Object?> row(String table, String id) =>
      _rows(db.raw, 'SELECT * FROM $table WHERE id = ?', [id]).single;
}

List<Map<String, Object?>> _rows(
  Database db,
  String sql, [
  List<Object?> params = const [],
]) {
  return [
    for (final row in db.select(sql, params))
      {for (final k in row.keys) k: row[k]},
  ];
}

_Env _env([String? path, bool closeAtTearDown = true]) {
  final db = LocalDatabase.open(path ?? _path());
  if (closeAtTearDown) {
    addTearDown(db.close);
  }
  final ids = _ids();
  final repo = SqliteTaskRepository(
    db,
    ownerId: 'owner-1',
    now: _clock,
    ids: ids,
  );
  // The store uses its own id space so its ids never collide with the repository's.
  final store = OutboxStore(
    db,
    ids: SequentialIdGenerator([for (var i = 0; i < 2000; i++) 'sid-$i']),
    now: _clock,
  );
  return _Env(db, repo, store);
}

Map<String, Object?> _applied(
  String operationId, {
  required int before,
  required int applied,
  Map<String, Object?>? row,
}) {
  return {
    'operation_id': operationId,
    'status': 'applied',
    'version_before': before,
    'applied_version': applied,
    'row': row ?? {'version': applied},
    'replayed': false,
  };
}

Future<void> _syncAll(_Env env, {int firstVersion = 1}) async {
  // Claims and acknowledges until nothing is claimable, as a server that applies
  // everything would; each applied create gets [firstVersion].
  for (var i = 0; i < 20; i++) {
    final batch = env.store.claimBatch();
    if (batch.isEmpty) {
      return;
    }
    env.store.acknowledge(
      [for (final op in batch) op.operationId],
      [
        for (final op in batch)
          _applied(
            op.operationId,
            before: op.opType == 'create' ? 0 : op.baseVersion,
            applied: op.opType == 'create' ? firstVersion : op.baseVersion + 1,
          ),
      ],
    );
  }
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-obx-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('rule R (wire base)', () {
    test('a create always sends base 0', () {
      expect(computeWireBase(opType: 'create', observedBase: 0), 0);
    });

    test('the predecessor own step moves the base to its applied version', () {
      expect(
        computeWireBase(
          opType: 'update',
          observedBase: 3,
          predecessorAppliedVersion: 4,
          predecessorVersionBefore: 3,
        ),
        4,
      );
    });

    test(
      'the counterexample: another device changed the entity, the base stays',
      () {
        // V = 3; device B moved the entity to 4; P applied at 5 (before = 4).
        expect(
          computeWireBase(
            opType: 'update',
            observedBase: 3,
            predecessorAppliedVersion: 5,
            predecessorVersionBefore: 4,
          ),
          3,
        );
      },
    );

    test('behind an unacknowledged create (observed 0) the base is the create version', () {
      expect(
        computeWireBase(
          opType: 'update',
          observedBase: 0,
          predecessorAppliedVersion: 1,
          predecessorVersionBefore: 0,
        ),
        1,
      );
    });

    test('with no applied predecessor the observed base is used; 0 is not sendable', () {
      expect(computeWireBase(opType: 'update', observedBase: 3), 3);
      expect(computeWireBase(opType: 'delete', observedBase: 0), isNull);
    });
  });

  group('claim rule and dependencies', () {
    test(
      'a child create waits for its project create to be acknowledged',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await env.repo.saveTask(makeTask(id: 't1', projectId: 'p1'));

        final first = env.store.claimBatch();
        expect(first.map((o) => o.entityId), ['p1']);
        expect(
          env.store.claimBatch(),
          isEmpty,
        ); // t1 still waits, p1 is in flight
        env.store.acknowledge(
          [first.single.operationId],
          [_applied(first.single.operationId, before: 0, applied: 1)],
        );

        final second = env.store.claimBatch();
        expect(second.map((o) => o.entityId), ['t1']);
        expect(second.single.baseVersion, 0);
        expect(second.single.wire['op_type'], 'create');
        expect(second.single.wire['base_version'], 0);
        expect(second.single.wire.containsKey('patch'), isTrue);
      },
    );

    test('never two operations of one entity in a batch, and one in flight per entity', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await _syncAll(env);
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'A', position: 0),
      );
      final first = env.store.claimBatch();
      expect(first, hasLength(1));
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'B', position: 0),
      );

      expect(
        env.ops("state = 'pending'"),
        hasLength(1),
      ); // a new dependent operation
      expect(env.store.claimBatch(), isEmpty);
    });

    test('unclassified and local-only entities are never claimed', () async {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        v1Project('p1', version: 3),
        v1Task('t1', 'p1'),
        v1Op('x', 'task', 't1', v1TaskPayload('t1', 'p1'), state: 'sent'),
      ]);
      final env = _env(path);

      expect(env.store.claimBatch(), isEmpty);
      expect(env.ops(), isEmpty);
    });

    test('a batch stops at 100 operations', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await _syncAll(env);
      for (var i = 0; i < 105; i++) {
        await env.repo.saveTask(
          makeTask(id: 't$i', projectId: 'p1', title: 'T$i'),
        );
      }

      final batch = env.store.claimBatch();

      expect(batch, hasLength(100));
    });

    test('a batch stops at 896 KiB of payload', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await _syncAll(env);
      final notes = 'x' * 200000;
      for (var i = 0; i < 6; i++) {
        await env.repo.saveTask(
          makeTask(id: 't$i', projectId: 'p1', notes: notes),
        );
      }

      final batch = env.store.claimBatch();

      expect(
        batch.length,
        lessThanOrEqualTo(4),
      ); // 4 x 200 KB < 896 KiB < 5 x 200 KB
      expect(batch.length, greaterThan(0));
      final sum = batch.fold<int>(
        0,
        (a, b) => a + utf8.encode(jsonEncode(b.wire['patch'])).length,
      );
      expect(sum, lessThanOrEqualTo(maxBatchPayloadBytes));
    });

    test('a payload over 224 KiB is refused and nothing is written', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final before = env.ops().length;

      await expectLater(
        env.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', notes: 'x' * 229400),
        ),
        throwsA(isA<RepositoryException>()),
      );

      expect(env.ops().length, before);
      expect(
        _rows(env.db.raw, "SELECT id FROM tasks WHERE id = 't1'"),
        isEmpty,
      );
    });
  });

  group('rule R in operation', () {
    test(
      'the predecessor own step raises the base; another device keeps it',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await _syncAll(env, firstVersion: 3);
        expect(env.row('projects', 'p1')['version'], 3);

        // E1 in flight; E2 queued behind it with the same observed base 3.
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'E1', position: 0),
        );
        final e1 = env.store.claimBatch().single;
        expect(e1.baseVersion, 3);
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'E1', position: 9),
        );
        final e2Row = env.ops("state = 'pending'").single;
        expect(e2Row['observed_base_version'], 3);
        expect(e2Row['depends_on_seq'], e1.seq);

        // Case 1: nothing but E1 happened (version_before 3, applied 4): E2 -> base 4.
        env.store.acknowledge(
          [e1.operationId],
          [_applied(e1.operationId, before: 3, applied: 4)],
        );
        final e2 = env.store.claimBatch().single;
        expect(e2.baseVersion, 4);
        expect(e2.wire['base_version'], 4);
      },
    );

    test('with another device in between (version_before 4) the observed base 3 stays', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await _syncAll(env, firstVersion: 3);
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'E1', position: 0),
      );
      final e1 = env.store.claimBatch().single;
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'E1', position: 9),
      );

      env.store.acknowledge(
        [e1.operationId],
        [_applied(e1.operationId, before: 4, applied: 5)],
      );
      final e2 = env.store.claimBatch().single;

      expect(e2.baseVersion, 3); // never blindly rebased to 5
    });

    test('an edit queued behind an unacknowledged create waits and then takes the create version', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final create = env.store.claimBatch().single; // the create is in flight
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Renamed', position: 0),
      );
      final edit = env.ops("state = 'pending'").single;
      expect(edit['op_type'], 'update');
      expect(edit['observed_base_version'], 0);
      expect(edit['depends_on_seq'], create.seq);
      expect(env.store.claimBatch(), isEmpty);

      env.store.acknowledge(
        [create.operationId],
        [_applied(create.operationId, before: 0, applied: 1)],
      );

      final next = env.store.claimBatch().single;
      expect(next.opType, 'update');
      expect(next.baseVersion, 1);
    });

    test(
      'the claimed operation is frozen: a retry sends the identical operation',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await _syncAll(env, firstVersion: 3);
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'E1', position: 0),
        );
        final first = env.store.claimBatch().single;
        env.store.releaseClaims([first.operationId], error: 'timeout');

        final again = env.store.claimBatch().single;

        expect(again.operationId, first.operationId);
        expect(jsonEncode(again.wire), jsonEncode(first.wire));
        expect(again.seq, first.seq);
      },
    );

    test('a later edit never folds into a claimed operation', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final create = env.store.claimBatch().single;
      env.store.releaseClaims([
        create.operationId,
      ]); // pending again, but claimed once

      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Renamed', position: 0),
      );

      expect(env.ops(), hasLength(2));
      expect(
        jsonDecode(env.ops().first['payload_json'] as String)['name'],
        'Home',
      );
    });
  });

  group('acknowledgement', () {
    test(
      'applied: state, version and snapshot are stored from the result',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        final op = env.store.claimBatch().single;

        final summary = env.store.acknowledge(
          [op.operationId],
          [
            _applied(
              op.operationId,
              before: 0,
              applied: 7,
              row: {'id': 'p1', 'name': 'Home', 'version': 7},
            ),
          ],
        );

        expect(summary.applied, 1);
        final row = env.ops().single;
        expect(row['state'], 'applied');
        expect(row['applied_version'], 7);
        expect(row['version_before'], 0);
        expect(
          jsonDecode(row['server_result_json'] as String)['status'],
          'applied',
        );
        expect(env.row('projects', 'p1')['version'], 7);
        final snap = _rows(
          env.db.raw,
          'SELECT * FROM sync_entity_snapshot',
        ).single;
        expect(snap['server_version'], 7);
        expect(snap['source'], 'ack');
      },
    );

    test('results are matched by operation_id, not position', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'A', position: 0),
      );
      await env.repo.saveProject(
        const Project(id: 'p2', name: 'B', position: 1),
      );
      final batch = env.store.claimBatch();
      expect(batch, hasLength(2));

      env.store.acknowledge(
        [for (final o in batch) o.operationId],
        [
          _applied(batch[1].operationId, before: 0, applied: 22),
          _applied(batch[0].operationId, before: 0, applied: 11),
        ],
      );

      expect(env.row('projects', batch[0].entityId)['version'], 11);
      expect(env.row('projects', batch[1].entityId)['version'], 22);
    });

    test('a wrong count, unknown id, duplicate or unknown status changes nothing', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'A', position: 0),
      );
      await env.repo.saveProject(
        const Project(id: 'p2', name: 'B', position: 1),
      );
      final batch = env.store.claimBatch();
      final ids = [for (final o in batch) o.operationId];
      final good = _applied(ids[0], before: 0, applied: 1);

      expect(
        () => env.store.acknowledge(ids, [good]),
        throwsA(isA<OutboxProtocolException>()),
      );
      expect(
        () => env.store.acknowledge(ids, [
          good,
          _applied('nope', before: 0, applied: 1),
        ]),
        throwsA(isA<OutboxProtocolException>()),
      );
      expect(
        () => env.store.acknowledge(ids, [good, good]),
        throwsA(isA<OutboxProtocolException>()),
      );
      expect(
        () => env.store.acknowledge(ids, 'x'),
        throwsA(isA<OutboxProtocolException>()),
      );
      expect(
        () => env.store.acknowledge(ids, [
          good,
          {'operation_id': ids[1], 'status': 'weird'},
        ]),
        throwsA(isA<OutboxProtocolException>()),
      );

      // Atomic: the valid first result was rolled back with the bad second one.
      expect(env.ops().map((r) => r['state']), ['in_flight', 'in_flight']);
      env.store.releaseClaims(ids);
      expect(env.ops().map((r) => r['state']), ['pending', 'pending']);
    });

    test('acknowledging the same operation twice is refused', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'A', position: 0),
      );
      final op = env.store.claimBatch().single;
      final result = _applied(op.operationId, before: 0, applied: 1);
      env.store.acknowledge([op.operationId], [result]);

      expect(
        () => env.store.acknowledge([op.operationId], [result]),
        throwsA(isA<OutboxProtocolException>()),
      );
    });

    test(
      'an auto-resolved sort_order is mirrored as resolved by policy',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'A', position: 0),
        );
        final op = env.store.claimBatch().single;

        env.store.acknowledge(
          [op.operationId],
          [
            {
              ..._applied(op.operationId, before: 0, applied: 2),
              'auto_resolved': true,
              'conflict_id': 'c-auto',
              'conflict': {
                'kind': 'field',
                'fields': ['sort_order'],
                'base_version': 0,
                'server_version': 1,
                'server_value': {'sort_order': 5},
                'client_value': {'sort_order': 9},
                'status': 'resolved_server',
              },
            },
          ],
        );

        final mirror = _rows(
          env.db.raw,
          'SELECT * FROM sync_conflicts_local',
        ).single;
        expect(mirror['id'], 'c-auto');
        expect(mirror['status'], 'resolved_server');
        expect(mirror['resolution_source'], 'auto_policy');
        expect(env.ops().single['state'], 'applied');
      },
    );
  });

  group('conflicts', () {
    Future<(_Env, ClaimedOperation)> conflicted() async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await _syncAll(env, firstVersion: 1);
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Mine', position: 0),
      );
      final op = env.store.claimBatch().single;
      env.store.acknowledge(
        [op.operationId],
        [
          {
            'operation_id': op.operationId,
            'status': 'conflict',
            'version_before': 2,
            'conflict_id': 'c1',
            'row': {
              'id': 'p1',
              'name': 'Theirs',
              'sort_order': 0,
              'version': 2,
            },
            'conflict': {
              'kind': 'field',
              'fields': ['name'],
              'base_version': 1,
              'server_version': 2,
              'server_value': {'name': 'Theirs'},
              'client_value': {'name': 'Mine'},
              'status': 'open',
            },
            'replayed': false,
          },
        ],
      );
      return (env, op);
    }

    test(
      'the conflict is mirrored with its evidence and the entity is held',
      () async {
        final (env, op) = await conflicted();

        final mirror = _rows(
          env.db.raw,
          'SELECT * FROM sync_conflicts_local',
        ).single;
        expect(mirror['kind'], 'field');
        expect(jsonDecode(mirror['fields_json'] as String), ['name']);
        expect(jsonDecode(mirror['server_value_json'] as String), {
          'name': 'Theirs',
        });
        expect(jsonDecode(mirror['client_value_json'] as String), {
          'name': 'Mine',
        });
        expect(mirror['status'], 'open');
        expect(env.ops().last['state'], 'conflict');
        expect(env.ops().last['operation_id'], op.operationId);
        expect(
          env.row('projects', 'p1')['version'],
          1,
        ); // a conflict never changes the version
        expect(
          env.row('projects', 'p1')['name'],
          'Mine',
        ); // local data is preserved
        final snap = _rows(
          env.db.raw,
          "SELECT * FROM sync_entity_snapshot WHERE source = 'conflict'",
        ).single;
        expect(snap['server_version'], 2);

        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Mine again', position: 0),
        );
        expect(env.store.claimBatch(), isEmpty); // the successor is held
      },
    );

    test('use server restores the entity from the snapshot and archives pending work', () async {
      final (env, _) = await conflicted();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Mine again', position: 0),
      );

      env.store.resolveConflictUseServer('c1');

      expect(env.row('projects', 'p1')['name'], 'Theirs');
      expect(env.row('projects', 'p1')['version'], 2);
      expect(
        _rows(
          env.db.raw,
          'SELECT status, resolution_source FROM sync_conflicts_local',
        ).single,
        {'status': 'resolved_server', 'resolution_source': 'user_use_server'},
      );
      expect(
        _rows(
          env.db.raw,
          "SELECT archive_reason FROM sync_outbox_archive WHERE source = 'v2'",
        ).single['archive_reason'],
        'resolved_use_server',
      );
      expect(env.ops("state = 'pending'"), isEmpty);
      expect(env.ops("state = 'conflict'").single['handled_at_utc'], isNotNull);
    });

    test(
      'retry local sends a new operation based on the server version',
      () async {
        final (env, old) = await conflicted();

        final id = env.store.resolveConflictRetryLocal('c1');

        expect(id, isNotNull);
        expect(id, isNot(old.operationId));
        final fresh = env.ops("operation_id = '$id'").single;
        expect(fresh['op_type'], 'update');
        expect(fresh['observed_base_version'], 2);
        expect(jsonDecode(fresh['payload_json'] as String), {'name': 'Mine'});
        expect(
          env.ops("operation_id = '${old.operationId}'").single['state'],
          'conflict',
        ); // history kept
        final next = env.store.claimBatch().single;
        expect(next.operationId, id);
        expect(next.baseVersion, 2);
      },
    );

    test('a resolved conflict cannot be resolved again', () async {
      final (env, _) = await conflicted();
      env.store.resolveConflictUseServer('c1');

      expect(
        () => env.store.resolveConflictUseServer('c1'),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('rejections', () {
    test('recovery uses a new operation id; the rejected operation stays as history', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final op = env.store.claimBatch().single;
      env.store.acknowledge(
        [op.operationId],
        [
          {
            'operation_id': op.operationId,
            'status': 'rejected',
            'error_code': 'invalid_patch',
            'replayed': false,
          },
        ],
      );
      expect(env.store.claimBatch(), isEmpty); // held until handled
      final payloadBefore = env.ops().single['payload_json'];

      final id = env.store.resubmitRejected(op.operationId);

      expect(id, isNot(op.operationId));
      final rejected = env.ops("operation_id = '${op.operationId}'").single;
      expect(rejected['state'], 'rejected');
      expect(rejected['error_code'], 'invalid_patch');
      expect(rejected['payload_json'], payloadBefore); // immutable
      expect(rejected['handled_at_utc'], isNotNull);
      final fresh = env.ops("operation_id = '$id'").single;
      expect(fresh['op_type'], 'create');
      expect(fresh['state'], 'pending');
      final again = env.store.claimBatch().single;
      expect(again.operationId, id);
      expect(
        () => env.store.resubmitRejected(op.operationId),
        throwsA(isA<RepositoryException>()),
      );
    });

    test(
      'discard local restores the last server snapshot and sends nothing',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await _syncAll(env, firstVersion: 4);
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Bad name', position: 0),
        );
        final op = env.store.claimBatch().single;
        env.store.acknowledge(
          [op.operationId],
          [
            {
              'operation_id': op.operationId,
              'status': 'rejected',
              'error_code': 'invalid_patch',
              'replayed': false,
            },
          ],
        );
        // The ack of the create stored a snapshot with the server row.
        env.db.raw.execute(
          "UPDATE sync_entity_snapshot SET row_json = '{\"name\":\"Home\",\"sort_order\":0,\"version\":4}'",
        );

        env.store.discardLocalAfterRejection(op.operationId);

        expect(env.row('projects', 'p1')['name'], 'Home');
        expect(env.ops("state = 'pending'"), isEmpty);
        expect(env.store.claimBatch(), isEmpty);
      },
    );
  });

  group('crash and restart recovery', () {
    test('in-flight operations return to pending unchanged and a second call is a no-op', () async {
      final path = _path();
      final env = _env(path, false);
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final op = env.store.claimBatch().single;
      env.db.close(); // the process dies with the operation in flight

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final store = OutboxStore(reopened, ids: _ids(), now: _clock);

      expect(store.recoverInFlight(), 1);
      expect(store.recoverInFlight(), 0);
      final row = _rows(reopened.raw, 'SELECT * FROM sync_outbox').single;
      expect(row['state'], 'pending');
      expect(row['operation_id'], op.operationId);
      expect(row['base_version'], 0);
      final again = store.claimBatch().single;
      expect(jsonEncode(again.wire), jsonEncode(op.wire));
    });

    test('seq order survives a restart', () async {
      final path = _path();
      final env = _env(path, false);
      for (var i = 0; i < 5; i++) {
        await env.repo.saveProject(
          Project(id: 'p$i', name: 'P$i', position: i),
        );
      }
      env.db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);

      final seqs = _rows(
        reopened.raw,
        'SELECT seq, entity_id FROM sync_outbox ORDER BY seq',
      );
      expect(seqs.map((r) => r['entity_id']), ['p0', 'p1', 'p2', 'p3', 'p4']);
    });

    test('the device id is created once and persisted', () async {
      final path = _path();
      final env = _env(path, false);
      final first = env.store.deviceId();
      expect(env.store.deviceId(), first);
      env.db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);

      expect(OutboxStore(reopened, ids: _ids()).deviceId(), 'sid-0');
      expect(first, 'sid-0');
    });
  });

  group('repository behaviors', () {
    test(
      'an edit of a synchronized task is a changed-fields-only patch',
      () async {
        final env = _env();
        await env.repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await env.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', title: 'A', notes: 'n'),
        );
        await _syncAll(env, firstVersion: 2);

        await env.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', title: 'B', notes: 'n'),
        );

        final edit = env.ops("state = 'pending'").single;
        expect(jsonDecode(edit['payload_json'] as String), {'title': 'B'});
      },
    );

    test('an unchanged save writes no operation', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await _syncAll(env);
      final before = env.ops().length;

      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );

      expect(env.ops().length, before);
    });

    test('completed_at is derived: set exactly while done, null for every other status', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await env.repo.saveTask(makeTask(id: 't1', projectId: 'p1'));
      await _syncAll(env, firstVersion: 2);

      await env.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', status: TaskStatus.done),
      );
      final done = env.row('tasks', 't1');
      expect(done['completed_at'], '2026-11-12T10:00:00.000Z');
      final patch = jsonDecode(
        env.ops("state = 'pending'").single['payload_json'] as String,
      ) as Map;
      expect(patch['status'], 'done');
      expect(patch['completed_at'], '2026-11-12T10:00:00.000Z');

      await env.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', status: TaskStatus.review),
      );
      expect(env.row('tasks', 't1')['completed_at'], isNull);
      await env.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', status: TaskStatus.done),
      );
      await env.repo.saveTask(
        makeTask(id: 't1', projectId: 'p1', status: TaskStatus.archived),
      );
      expect(env.row('tasks', 't1')['completed_at'], isNull);
    });

    test('a task cannot move to another project', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'A', position: 0),
      );
      await env.repo.saveProject(
        const Project(id: 'p2', name: 'B', position: 1),
      );
      await env.repo.saveTask(makeTask(id: 't1', projectId: 'p1'));

      await expectLater(
        env.repo.saveTask(makeTask(id: 't1', projectId: 'p2')),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('a task with live subtasks cannot be deleted; a leaf can', () async {
      final env = _env();
      await env.repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await env.repo.saveTask(makeTask(id: 'parent', projectId: 'p1'));
      await env.repo.saveTask(
        makeTask(id: 'child', projectId: 'p1', parentId: 'parent'),
      );

      await expectLater(
        env.repo.softDeleteTask('parent'),
        throwsA(isA<RepositoryException>()),
      );
      expect(env.row('tasks', 'parent')['deleted_at'], isNull);

      await env.repo.softDeleteTask('child');
      await env.repo.softDeleteTask('parent');
      expect(env.row('tasks', 'parent')['deleted_at'], isNotNull);
      final deletes = env.ops("op_type = 'delete'");
      expect(deletes, hasLength(2));
      expect(
        deletes.every((r) => r['depends_on_seq'] != null),
        isTrue,
      ); // behind their creates
    });

    test('demo data and everything created under it stay local-only', () async {
      final env = _env();
      final demo = buildDemoData(const CalendarDate(2026, 11, 12));
      await env.repo.seedDemoData(projects: demo.projects, tasks: demo.tasks);
      expect(env.ops(), isEmpty);
      final demoProject = demo.projects.first;

      await env.repo.saveTask(
        makeTask(id: 'mine', projectId: demoProject.id, title: 'Mine'),
      );
      final existing = demo.tasks.first;
      await env.repo.saveTask(
        makeTask(
          id: existing.id,
          projectId: existing.projectId,
          title: 'Edited demo',
        ),
      );

      expect(env.ops(), isEmpty);
      expect(env.row('tasks', 'mine')['sync_scope'], 'local_only');
      expect(
        _rows(
          env.db.raw,
          "SELECT COUNT(*) AS n FROM tasks WHERE sync_scope <> 'local_only'",
        ).single['n'],
        0,
      );
      expect(
        _rows(
          env.db.raw,
          "SELECT COUNT(*) AS n FROM projects WHERE sync_scope <> 'local_only'",
        ).single['n'],
        0,
      );
      expect(env.store.claimBatch(), isEmpty);
    });

    test(
      'a new project beside demo data is synchronized and its tasks follow it',
      () async {
        final env = _env();
        final demo = buildDemoData(const CalendarDate(2026, 11, 12));
        await env.repo.seedDemoData(projects: demo.projects, tasks: demo.tasks);

        await env.repo.saveProject(
          const Project(id: 'mine', name: 'Mine', position: 99),
        );
        await env.repo.saveTask(makeTask(id: 'tm', projectId: 'mine'));

        expect(env.row('projects', 'mine')['sync_scope'], 'synced');
        expect(env.ops().map((r) => r['entity_id']), ['mine', 'tm']);
      },
    );

    test(
      'edits to an unclassified (migrated legacy) entity write no operation',
      () async {
        final path = _path();
        createV1File(path, [
          "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
          v1Project('p1', version: 3, name: 'Legacy'),
          v1Task('t1', 'p1', title: 'Legacy task', version: 2),
          v1Op('x', 'task', 't1', v1TaskPayload('t1', 'p1'), state: 'acked'),
        ]);
        final env = _env(path);

        await env.repo.saveTask(
          makeTask(id: 't1', projectId: 'p1', title: 'Edited'),
        );
        await env.repo.saveTask(
          makeTask(id: 'new', projectId: 'p1', title: 'New under legacy'),
        );

        expect(env.ops(), isEmpty);
        expect(env.row('tasks', 't1')['title'], 'Edited');
        expect(env.row('tasks', 't1')['version'], 2); // never reset
        expect(env.row('tasks', 'new')['sync_scope'], 'unclassified');
      },
    );

    test('the user binding refuses a second user', () {
      final env = _env();
      env.db.bindUser('owner-1');

      expect(
        () => env.db.bindUser('owner-2'),
        throwsA(isA<RepositoryException>()),
      );
    });
  });
}
