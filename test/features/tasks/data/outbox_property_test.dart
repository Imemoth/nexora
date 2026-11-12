import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/sequential_id_generator.dart';

/// Model-based property test of the outbox against a fake server that implements
/// the S2 conflict rule (a field conflicts iff its field version is greater than
/// the wire base) and replays results by operation id.
///
/// Property (the safety half of rule R): an update the server applies never
/// overwrites a field that another device changed after the update's **observed**
/// basis. A blind rebase to the predecessor's applied version would break it.
/// Also: at most one operation in flight, claimed payloads never change, a retry
/// sends the identical operation, and no operation is sent with a base ahead of
/// the server.
final class _FakeServer {
  int version = 0;
  final Map<String, Object?> values = {};
  final Map<String, int> fieldVersions = {};
  final Map<String, int> lastOtherVersion = {};
  final Map<String, Map<String, Object?>> stored = {};
  final List<String> violations = [];

  Map<String, Object?> _row() => {
    'id': 'p1',
    ...values,
    'version': version,
  };

  void otherEdit(String field, Object? value) {
    if (values[field] == value) {
      return;
    }
    version++;
    values[field] = value;
    fieldVersions[field] = version;
    lastOtherVersion[field] = version;
  }

  List<Map<String, Object?>> process(
    List<Map<String, Object?>> ops,
    int Function(String operationId) observedOf,
  ) {
    final results = <Map<String, Object?>>[];
    for (final op in ops) {
      final id = op['operation_id']! as String;
      final replay = stored[id];
      if (replay != null) {
        results.add({...replay, 'replayed': true});
        continue;
      }
      final result = _apply(op, observedOf(id));
      stored[id] = result;
      results.add(result);
    }
    return results;
  }

  Map<String, Object?> _apply(Map<String, Object?> op, int observed) {
    final id = op['operation_id']! as String;
    final type = op['op_type'];
    if (type == 'create') {
      values
        ..clear()
        ..addAll(Map<String, Object?>.from(op['patch']! as Map));
      version = 1;
      fieldVersions.clear();
      return {
        'operation_id': id,
        'status': 'applied',
        'version_before': 0,
        'applied_version': 1,
        'row': _row(),
        'replayed': false,
      };
    }
    final base = op['base_version']! as int;
    if (base > version || base < 1) {
      violations.add('op $id sent with base $base but the server is at $version');
      return {'operation_id': id, 'status': 'rejected', 'error_code': 'invalid_op', 'replayed': false};
    }
    final patch = Map<String, Object?>.from((op['patch'] ?? <String, Object?>{}) as Map);
    final conflicting = <String>[];
    for (final entry in patch.entries) {
      if (values[entry.key] == entry.value) {
        continue;
      }
      if ((fieldVersions[entry.key] ?? 0) > base) {
        conflicting.add(entry.key);
      }
    }
    if (conflicting.isNotEmpty) {
      conflicting.sort();
      return {
        'operation_id': id,
        'status': 'conflict',
        'version_before': version,
        'conflict_id': 'c-$id',
        'row': _row(),
        'conflict': {
          'kind': 'field',
          'fields': conflicting,
          'base_version': base,
          'server_version': version,
          'server_value': {for (final f in conflicting) f: values[f]},
          'client_value': {for (final f in conflicting) f: patch[f]},
          'status': 'open',
        },
        'replayed': false,
      };
    }
    final before = version;
    final changed = [
      for (final entry in patch.entries)
        if (values[entry.key] != entry.value) entry.key,
    ];
    if (changed.isNotEmpty) {
      version++;
    }
    for (final field in changed) {
      if ((lastOtherVersion[field] ?? 0) > observed) {
        violations.add(
          'op $id overwrote "$field", changed by another device at version '
          '${lastOtherVersion[field]} after its observed base $observed (wire base $base)',
        );
      }
      values[field] = patch[field];
      fieldVersions[field] = version;
    }
    return {
      'operation_id': id,
      'status': 'applied',
      'version_before': before,
      'applied_version': version,
      'row': _row(),
      'replayed': false,
    };
  }
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nexora-prop-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('rule R never hides a conflict, and the outbox stays consistent (40 seeds)', () async {
    for (var seed = 0; seed < 40; seed++) {
      await _scenario(seed, dir);
    }
  });
}

Future<void> _scenario(int seed, Directory dir) async {
  final rng = Random(seed);
  final db = LocalDatabase.open('${dir.path}${Platform.pathSeparator}prop-$seed.db');
  try {
    final repo = SqliteTaskRepository(
      db,
      ownerId: 'o',
      now: () => DateTime.utc(2026, 11, 12, 10),
      ids: SequentialIdGenerator([for (var i = 0; i < 4000; i++) 'op-$seed-$i']),
    );
    final store = OutboxStore(
      db,
      ids: SequentialIdGenerator([for (var i = 0; i < 4000; i++) 'rq-$seed-$i']),
    );
    final server = _FakeServer();
    final claimedPayloads = <String, String>{};

    int observedOf(String operationId) {
      return db.select(
            'SELECT observed_base_version AS v FROM sync_outbox WHERE operation_id = ?',
            [operationId],
          ).single['v']!
          as int;
    }

    void ack(List<ClaimedOperation> batch, List<Map<String, Object?>> results) {
      store.acknowledge([for (final op in batch) op.operationId], results);
      for (final conflict in db.select("SELECT id FROM sync_conflicts_local WHERE status = 'open'")) {
        store.resolveConflictUseServer(conflict['id'] as String);
      }
    }

    void pump() {
      final batch = store.claimBatch();
      if (batch.isEmpty) {
        return;
      }
      expect(
        db.select("SELECT COUNT(*) AS n FROM sync_outbox WHERE state = 'in_flight'").single['n'],
        lessThanOrEqualTo(1),
        reason: 'seed $seed: one in flight per entity',
      );
      for (final op in batch) {
        final payload = db.select('SELECT payload_json FROM sync_outbox WHERE seq = ?', [op.seq]).single['payload_json'] as String;
        final seen = claimedPayloads[op.operationId];
        expect(seen == null || seen == payload, isTrue, reason: 'seed $seed: claimed payload changed');
        claimedPayloads[op.operationId] = payload;
      }
      final wires = [for (final op in batch) op.wire];
      if (rng.nextInt(100) < 15) {
        // The response is lost: the server applied it, the client times out and
        // retries the identical operations, and the server replays them.
        server.process(wires, observedOf);
        store.releaseClaims([for (final op in batch) op.operationId], error: 'timeout');
        final again = store.claimBatch();
        expect(
          [for (final op in again) op.operationId],
          [for (final op in batch) op.operationId],
          reason: 'seed $seed: retry sends the same operations',
        );
        for (var i = 0; i < again.length; i++) {
          expect(again[i].wire, batch[i].wire, reason: 'seed $seed: retry is identical');
        }
        ack(again, server.process([for (final op in again) op.wire], observedOf));
      } else {
        ack(batch, server.process(wires, observedOf));
      }
    }

    Map<String, Object?> local() {
      final row = db.select("SELECT name, sort_order FROM projects WHERE id = 'p1'").single;
      return {'name': row['name'], 'sort_order': row['sort_order']};
    }

    await repo.saveProject(const Project(id: 'p1', name: 'n0', position: 0));
    pump();
    for (var step = 0; step < 28; step++) {
      final roll = rng.nextInt(10);
      if (roll < 4) {
        final current = local();
        final name = rng.nextBool() ? 'n${rng.nextInt(5)}' : current['name']! as String;
        final position = rng.nextBool() ? rng.nextInt(5) : current['sort_order']! as int;
        await repo.saveProject(Project(id: 'p1', name: name, position: position));
      } else if (roll < 7) {
        pump();
      } else if (rng.nextBool()) {
        server.otherEdit('name', 'o${rng.nextInt(5)}');
      } else {
        server.otherEdit('sort_order', 10 + rng.nextInt(5));
      }
    }
    for (var i = 0; i < 30; i++) {
      pump();
    }

    expect(server.violations, isEmpty, reason: 'seed $seed');
    expect(
      db.select("SELECT COUNT(*) AS n FROM sync_outbox WHERE state = 'in_flight'").single['n'],
      0,
      reason: 'seed $seed',
    );
    final seqs = [for (final r in db.select('SELECT seq FROM sync_outbox ORDER BY seq')) r['seq'] as int];
    expect([...seqs]..sort(), seqs);
  } finally {
    db.close();
  }
}
