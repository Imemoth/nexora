import 'dart:convert';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:sqlite3/sqlite3.dart';

import 'entity_patch.dart';
import 'jsonb_size.dart';
import 'local_database.dart';
import 'schema_v2.dart';
import 'server_row.dart';

/// Operations per push call (wire contract: 1 to 100).
const int maxBatchOperations = 100;

/// Sum of payload bytes per batch: 896 KiB.
const int maxBatchPayloadBytes = 917504;

/// Exact serialized size of the whole `p_ops` array, as PostgreSQL prints it.
/// The server's hard limit is 1,048,576 bytes (`NX004`); this leaves headroom.
const int maxEnvelopeBytes = 1000000;

/// The server answered in a way the client cannot trust (wrong count, unknown or
/// duplicate operation id, missing fields). Nothing is acknowledged; the caller
/// releases the claims and retries the same batch unchanged.
final class OutboxProtocolException implements Exception {
  const OutboxProtocolException(this.message);

  final String message;

  @override
  String toString() => 'OutboxProtocolException: $message';
}

/// The wire base for [opType] (dependency-adjusted rule R, S5 spec section 2).
///
/// A create always sends base 0. For a later operation whose immediate
/// predecessor on the same entity was applied: if the predecessor's
/// `version_before` equals the operation's observed base, nothing but the
/// predecessor's own step happened after the observed basis, so the base moves
/// to the predecessor's `applied_version` (exact). Otherwise the observed base is
/// kept, which can produce a false conflict but never hides a real one. An
/// observed base of 0 (the operation was queued behind an unacknowledged create)
/// takes the predecessor's `applied_version`, because the wire requires a base of
/// at least 1. Returns null when no valid base exists (the operation is not
/// claimable).
int? computeWireBase({
  required String opType,
  required int observedBase,
  int? predecessorAppliedVersion,
  int? predecessorVersionBefore,
}) {
  if (opType == 'create') {
    return 0;
  }
  if (predecessorAppliedVersion != null) {
    if (observedBase == 0) {
      return predecessorAppliedVersion;
    }
    if (predecessorVersionBefore == observedBase) {
      return predecessorAppliedVersion;
    }
    return observedBase;
  }
  return observedBase >= 1 ? observedBase : null;
}

/// An operation handed to the transport, already `in_flight`.
final class ClaimedOperation {
  const ClaimedOperation({
    required this.seq,
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.opType,
    required this.baseVersion,
    required this.wire,
  });

  final int seq;
  final String operationId;
  final String entityType;
  final String entityId;
  final String opType;
  final int baseVersion;

  /// The operation exactly as it goes into `p_ops`.
  final Map<String, Object?> wire;
}

/// How many results of each status an acknowledgement processed.
final class AckSummary {
  const AckSummary({
    required this.applied,
    required this.conflicts,
    required this.rejected,
  });

  final int applied;
  final int conflicts;
  final int rejected;
}

/// The local outbox: recording changes, claiming operations for the transport,
/// processing acknowledgements, and the explicit recovery actions.
///
/// `record*` methods must run inside the caller's transaction (the repository
/// writes the domain row and the operation together). Every other public method
/// opens its own transaction.
final class OutboxStore {
  OutboxStore(this._db, {IdGenerator? ids, DateTime Function()? now})
    : _ids = ids ?? RandomIdGenerator(),
      _now = now ?? (() => DateTime.now().toUtc());

  final LocalDatabase _db;
  final IdGenerator _ids;
  final DateTime Function() _now;

  Database get _raw => _db.raw;

  // ------------------------------------------------------------- recording

  /// Queues the create of a new synchronized entity. [parentType] and [parentId]
  /// name the entity whose own create must be acknowledged first (a task's parent
  /// task, or its project).
  void recordCreate({
    required String entityType,
    required String entityId,
    required Map<String, Object?> patch,
    String? parentType,
    String? parentId,
  }) {
    final dependsOn = (parentType == null || parentId == null)
        ? null
        : _unfinishedCreateSeq(parentType, parentId);
    _insertOp(entityType, entityId, 'create', 0, patch, dependsOn);
  }

  /// Records a local edit of a synchronized entity as a changed-fields-only patch.
  /// It folds into the entity's newest operation when that is a never-claimed
  /// pending create, or a never-claimed pending update with the same observed
  /// basis; otherwise it becomes a new operation that waits for its predecessor.
  void recordEdit({
    required String entityType,
    required String entityId,
    required Map<String, Object?> patch,
    required int storedVersion,
  }) {
    if (patch.isEmpty) {
      return;
    }
    final last = _latestOp(entityType, entityId);
    if (last != null &&
        last['state'] == 'pending' &&
        last['base_version'] == null &&
        (last['op_type'] == 'create' ||
            (last['op_type'] == 'update' &&
                last['observed_base_version'] == storedVersion))) {
      final merged = Map<String, Object?>.from(
        jsonDecode(last['payload_json'] as String) as Map,
      )..addAll(patch);
      final payload = _encode(merged);
      _raw.execute(
        'UPDATE sync_outbox SET payload_json = ?, payload_bytes = ? WHERE seq = ?',
        [payload.json, payload.bytes, last['seq']],
      );
      return;
    }
    final dependsOn = (last != null && last['state'] != 'applied')
        ? last['seq'] as int
        : null;
    _insertOp(entityType, entityId, 'update', storedVersion, patch, dependsOn);
  }

  /// Records the tombstone of a synchronized entity. Never folded.
  void recordDelete({
    required String entityType,
    required String entityId,
    required int storedVersion,
  }) {
    final last = _latestOp(entityType, entityId);
    final dependsOn = (last != null && last['state'] != 'applied')
        ? last['seq'] as int
        : null;
    _insertOp(entityType, entityId, 'delete', storedVersion, null, dependsOn);
  }

  /// Records the atomic deletion of a subtree (S3 protocol extension): one
  /// delete operation for the root that lists every live descendant the client
  /// tombstoned. It waits until all earlier operations of those entities are
  /// finished, and its manifest of exact base versions is built when it is
  /// claimed. The server applies all of it or none of it.
  void recordDeleteTree({
    required String entityType,
    required String entityId,
    required int storedVersion,
    required List<String> descendantIds,
  }) {
    final last = _latestOp(entityType, entityId);
    final dependsOn = (last != null && last['state'] != 'applied')
        ? last['seq'] as int
        : null;
    _insertOp(entityType, entityId, 'delete', storedVersion, {
      'tree': descendantIds,
    }, dependsOn);
  }

  /// The descendant ids of a not yet claimed tree delete (`{"tree": [ids]}`), or
  /// null when the payload is not a local tree delete.
  List<String>? _localTreeIds(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map || decoded['tree'] is! List) {
      return null;
    }
    final list = decoded['tree'] as List;
    if (list.isNotEmpty && list.first is! String) {
      return null; // already a built manifest
    }
    return list.cast<String>();
  }

  /// Entity ids of a tree delete in either form (local ids or built manifest).
  List<String>? _treeIds(String payloadJson) {
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map || decoded['tree'] is! List) {
      return null;
    }
    return [
      for (final entry in decoded['tree'] as List)
        if (entry is String) entry else (entry as Map)['id'] as String,
    ];
  }

  bool _subtreeReady(Map<String, Object?> row, List<String> ids) {
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
      final marks = List.filled(chunk.length, '?').join(', ');
      final blocking = _rows(
        'SELECT 1 FROM sync_outbox e WHERE e.entity_type = \'task\' '
        'AND e.entity_id IN ($marks) AND e.seq < ? AND NOT ${_ok('e')} LIMIT 1',
        [...chunk, row['seq']],
      );
      if (blocking.isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  String _treeManifestJson(List<String> ids) {
    final entries = <Map<String, Object?>>[];
    for (var i = 0; i < ids.length; i += 400) {
      final chunk = ids.sublist(i, i + 400 > ids.length ? ids.length : i + 400);
      final marks = List.filled(chunk.length, '?').join(', ');
      for (final row in _rows(
        'SELECT id, version FROM tasks WHERE id IN ($marks)',
        chunk,
      )) {
        final version = row['version'] as int;
        if (version >= 1) {
          entries.add({'id': row['id'], 'base_version': version});
        }
      }
    }
    return jsonEncode({'tree': entries});
  }

  int _insertOp(
    String entityType,
    String entityId,
    String opType,
    int observedBase,
    Map<String, Object?>? patch,
    int? dependsOn,
  ) {
    final payload = _encode(patch ?? <String, Object?>{});
    _raw.execute(
      'INSERT INTO sync_outbox (operation_id, entity_type, entity_id, op_type, '
      'observed_base_version, base_version, payload_json, payload_bytes, '
      "created_at_utc, state, attempts, depends_on_seq) "
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?)",
      [
        _ids.nextId(),
        entityType,
        entityId,
        opType,
        observedBase,
        null,
        payload.json,
        payload.bytes,
        _iso(),
        dependsOn,
      ],
    );
    return _raw.lastInsertRowId;
  }

  ({String json, int bytes}) _encode(Map<String, Object?> patch) {
    final json = jsonEncode(patch);
    final bytes = utf8.encode(json).length;
    if (bytes > maxPayloadBytes) {
      throw const RepositoryException(
        'operation payload exceeds the 224 KiB limit',
      );
    }
    return (json: json, bytes: bytes);
  }

  int? _unfinishedCreateSeq(String entityType, String entityId) {
    final rows = _rows(
      'SELECT seq FROM sync_outbox WHERE entity_type = ? AND entity_id = ? '
      "AND op_type = 'create' AND state <> 'applied' ORDER BY seq DESC LIMIT 1",
      [entityType, entityId],
    );
    return rows.isEmpty ? null : rows.single['seq'] as int;
  }

  Map<String, Object?>? _latestOp(String entityType, String entityId) {
    final rows = _rows(
      'SELECT * FROM sync_outbox WHERE entity_type = ? AND entity_id = ? '
      'ORDER BY seq DESC LIMIT 1',
      [entityType, entityId],
    );
    return rows.isEmpty ? null : rows.single;
  }

  // ----------------------------------------------------------------- claim

  static const String _handledOrApplied =
      "(%s.state = 'applied' OR (%s.state IN ('conflict', 'rejected') "
      'AND %s.handled_at_utc IS NOT NULL))';

  static String _ok(String alias) => _handledOrApplied.replaceAll('%s', alias);

  /// Operations that may be sent now, oldest first: pending; every earlier
  /// operation on the entity is applied or handled; the operation it depends on
  /// is applied or handled; the entity is synchronized (never unclassified or
  /// local-only).
  static final String _claimableSql =
      'SELECT o.* FROM sync_outbox o WHERE o.state = \'pending\' '
      'AND NOT EXISTS (SELECT 1 FROM sync_outbox e '
      'WHERE e.entity_type = o.entity_type AND e.entity_id = o.entity_id '
      'AND e.seq < o.seq AND NOT ${_ok('e')}) '
      'AND (o.depends_on_seq IS NULL OR EXISTS (SELECT 1 FROM sync_outbox d '
      'WHERE d.seq = o.depends_on_seq AND ${_ok('d')})) '
      'AND ((o.entity_type = \'project\' AND EXISTS (SELECT 1 FROM projects p '
      'WHERE p.id = o.entity_id AND p.sync_scope = \'synced\')) '
      'OR (o.entity_type = \'task\' AND EXISTS (SELECT 1 FROM tasks t '
      'WHERE t.id = o.entity_id AND t.sync_scope = \'synced\'))) '
      'ORDER BY o.seq';

  /// Claims the next batch for the transport: marks the operations `in_flight`,
  /// freezes their wire base (rule R, only for a first claim) and returns them in
  /// `seq` order. Stops at 100 operations, 896 KiB of payload, or when the exact
  /// serialized batch would pass [maxEnvelopeBytes]. Never two operations of one
  /// entity, never an operation whose predecessor is unfinished.
  List<ClaimedOperation> claimBatch({int maxOperations = maxBatchOperations}) {
    final limit = maxOperations > maxBatchOperations
        ? maxBatchOperations
        : maxOperations;
    return _transaction(() {
      final claimed = <ClaimedOperation>[];
      final wires = <Map<String, Object?>>[];
      var payloadSum = 0;
      for (final row in _rows(_claimableSql)) {
        if (claimed.length >= limit) {
          break;
        }
        final bytes = row['payload_bytes'] as int;
        if (payloadSum + bytes > maxBatchPayloadBytes) {
          break;
        }
        final existing = row['base_version'] as int?;
        final base = existing ?? _wireBaseFor(row);
        if (base == null) {
          continue;
        }
        // A tree delete (S3) is claimed only when every earlier operation of every
        // listed entity is finished; its manifest of exact base versions is built
        // now, from the acknowledged local versions, and frozen with the claim.
        String? finalPayload;
        if (existing == null &&
            row['op_type'] == 'delete' &&
            _localTreeIds(row['payload_json'] as String) != null) {
          final ids = _localTreeIds(row['payload_json'] as String)!;
          if (!_subtreeReady(row, ids)) {
            continue;
          }
          finalPayload = _treeManifestJson(ids);
        }
        final wire = _wireOperation(row, base, payloadJson: finalPayload);
        if (jsonbTextBytes([...wires, wire]) > maxEnvelopeBytes) {
          break;
        }
        if (finalPayload != null) {
          _raw.execute(
            "UPDATE sync_outbox SET state = 'in_flight', "
            'base_version = COALESCE(base_version, ?), payload_json = ?, payload_bytes = ?, '
            'sent_at = ?, attempts = attempts + 1, request_id = ? WHERE seq = ?',
            [
              base,
              finalPayload,
              utf8.encode(finalPayload).length,
              _iso(),
              _ids.nextId(),
              row['seq'],
            ],
          );
        } else {
          _raw.execute(
            "UPDATE sync_outbox SET state = 'in_flight', "
            'base_version = COALESCE(base_version, ?), sent_at = ?, '
            'attempts = attempts + 1, request_id = ? WHERE seq = ?',
            [base, _iso(), _ids.nextId(), row['seq']],
          );
        }
        claimed.add(
          ClaimedOperation(
            seq: row['seq'] as int,
            operationId: row['operation_id'] as String,
            entityType: row['entity_type'] as String,
            entityId: row['entity_id'] as String,
            opType: row['op_type'] as String,
            baseVersion: base,
            wire: wire,
          ),
        );
        wires.add(wire);
        payloadSum += bytes;
      }
      return claimed;
    });
  }

  int? _wireBaseFor(Map<String, Object?> row) {
    final opType = row['op_type'] as String;
    final predecessor = _rows(
      'SELECT state, applied_version, version_before FROM sync_outbox '
      'WHERE entity_type = ? AND entity_id = ? AND seq < ? '
      'ORDER BY seq DESC LIMIT 1',
      [row['entity_type'], row['entity_id'], row['seq']],
    );
    final applied =
        predecessor.isNotEmpty && predecessor.single['state'] == 'applied';
    return computeWireBase(
      opType: opType,
      observedBase: row['observed_base_version'] as int,
      predecessorAppliedVersion: applied
          ? predecessor.single['applied_version'] as int?
          : null,
      predecessorVersionBefore: applied
          ? predecessor.single['version_before'] as int?
          : null,
    );
  }

  Map<String, Object?> _wireOperation(
    Map<String, Object?> row,
    int base, {
    String? payloadJson,
  }) {
    final wire = <String, Object?>{
      'operation_id': row['operation_id'],
      'entity_type': row['entity_type'],
      'entity_id': row['entity_id'],
      'op_type': row['op_type'],
      'base_version': base,
    };
    final patch = jsonDecode(payloadJson ?? row['payload_json'] as String);
    if (row['op_type'] != 'delete' || (patch is Map && patch.isNotEmpty)) {
      wire['patch'] = patch;
    }
    wire['client_created_at'] = row['created_at_utc'];
    return wire;
  }

  /// Returns claimed operations to `pending` after a call-level failure (timeout,
  /// 5xx, transient database error, malformed response). The retry sends the
  /// identical operation: payload and wire base are frozen once claimed.
  void releaseClaims(List<String> operationIds, {String? error}) {
    _transaction(() {
      for (final id in operationIds) {
        _raw.execute(
          "UPDATE sync_outbox SET state = 'pending', last_error = COALESCE(?, last_error) "
          "WHERE operation_id = ? AND state = 'in_flight'",
          [error, id],
        );
      }
    });
  }

  /// At start-up: every `in_flight` operation returns to `pending` (a crash may
  /// have lost the response; the server replays by `operation_id`). Idempotent.
  int recoverInFlight() {
    return _transaction(() {
      _raw.execute(
        "UPDATE sync_outbox SET state = 'pending' WHERE state = 'in_flight'",
      );
      return _raw.updatedRows;
    });
  }

  // ------------------------------------------------------- acknowledgement

  /// Processes the `results` of a push call for the operations [sentIds].
  /// Results are matched by `operation_id`; the count and the id set must equal
  /// what was sent. All results are processed in one transaction, so a malformed
  /// response changes nothing (it throws [OutboxProtocolException]).
  AckSummary acknowledge(List<String> sentIds, Object? results) {
    if (results is! List) {
      throw const OutboxProtocolException('results is not a list');
    }
    if (results.length != sentIds.length) {
      throw const OutboxProtocolException(
        'result count differs from sent count',
      );
    }
    final byId = <String, Map<String, Object?>>{};
    for (final result in results) {
      if (result is! Map) {
        throw const OutboxProtocolException('a result is not an object');
      }
      final id = result['operation_id'];
      if (id is! String || byId.containsKey(id)) {
        throw const OutboxProtocolException(
          'missing or duplicate operation_id',
        );
      }
      byId[id] = Map<String, Object?>.from(result);
    }
    if (!sentIds.every(byId.containsKey)) {
      throw const OutboxProtocolException('result ids differ from sent ids');
    }
    return _transaction(() {
      var applied = 0;
      var conflicts = 0;
      var rejected = 0;
      for (final id in sentIds) {
        final result = byId[id]!;
        switch (result['status']) {
          case 'applied':
            _ackApplied(id, result);
            applied++;
          case 'conflict':
            _ackConflict(id, result);
            conflicts++;
          case 'rejected':
            _ackRejected(id, result);
            rejected++;
          default:
            throw const OutboxProtocolException('unknown result status');
        }
      }
      return AckSummary(
        applied: applied,
        conflicts: conflicts,
        rejected: rejected,
      );
    });
  }

  Map<String, Object?> _inFlight(String operationId) {
    final rows = _rows(
      "SELECT * FROM sync_outbox WHERE operation_id = ? AND state = 'in_flight'",
      [operationId],
    );
    if (rows.isEmpty) {
      throw const OutboxProtocolException('operation is not in flight');
    }
    return rows.single;
  }

  void _ackApplied(String operationId, Map<String, Object?> result) {
    final op = _inFlight(operationId);
    final version = result['applied_version'];
    if (version is! int) {
      throw const OutboxProtocolException(
        'applied result without applied_version',
      );
    }
    final before = result['version_before'];
    _raw.execute(
      "UPDATE sync_outbox SET state = 'applied', applied_version = ?, "
      'version_before = ?, server_result_json = ?, last_error = NULL WHERE seq = ?',
      [version, before is int ? before : null, jsonEncode(result), op['seq']],
    );
    final entityType = op['entity_type'] as String;
    final entityId = op['entity_id'] as String;
    _snapshot(entityType, entityId, result['row'], 'ack');
    _raw.execute(
      'UPDATE ${_table(entityType)} SET version = MAX(version, ?) WHERE id = ?',
      [version, entityId],
    );
    final conflict = result['conflict'];
    final conflictId = result['conflict_id'];
    if (result['auto_resolved'] == true &&
        conflict is Map &&
        conflictId is String) {
      _insertMirror(
        id: conflictId,
        op: op,
        detail: Map<String, Object?>.from(conflict),
        status: 'resolved_server',
        source: 'auto_policy',
      );
    }
  }

  void _ackConflict(String operationId, Map<String, Object?> result) {
    final op = _inFlight(operationId);
    final conflictId = result['conflict_id'];
    if (conflictId is! String) {
      throw const OutboxProtocolException(
        'conflict result without conflict_id',
      );
    }
    final detail = result['conflict'];
    _raw.execute(
      "UPDATE sync_outbox SET state = 'conflict', conflict_id = ?, "
      'server_result_json = ? WHERE seq = ?',
      [conflictId, jsonEncode(result), op['seq']],
    );
    _insertMirror(
      id: conflictId,
      op: op,
      detail: detail is Map ? Map<String, Object?>.from(detail) : null,
      status: 'open',
      source: null,
    );
    _snapshot(
      op['entity_type'] as String,
      op['entity_id'] as String,
      result['row'],
      'conflict',
    );
  }

  void _ackRejected(String operationId, Map<String, Object?> result) {
    final op = _inFlight(operationId);
    final code = result['error_code'];
    final errorCode = code is String ? code : 'unknown';
    _raw.execute(
      "UPDATE sync_outbox SET state = 'rejected', error_code = ?, "
      'last_error = ?, server_result_json = ? WHERE seq = ?',
      [errorCode, errorCode, jsonEncode(result), op['seq']],
    );
  }

  void _insertMirror({
    required String id,
    required Map<String, Object?> op,
    required Map<String, Object?>? detail,
    required String status,
    required String? source,
  }) {
    final kind = detail?['kind'];
    final detailBase = detail?['base_version'];
    final detailServerVersion = detail?['server_version'];
    final now = _iso();
    _raw.execute(
      'INSERT INTO sync_conflicts_local (id, operation_id, entity_type, entity_id, '
      'kind, fields_json, base_version, server_version, server_value_json, '
      'client_value_json, status, resolution_source, created_at_utc, resolved_at_utc) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        id,
        op['operation_id'],
        op['entity_type'],
        op['entity_id'],
        conflictKinds.contains(kind) ? kind : 'field',
        jsonEncode(detail?['fields'] ?? <Object?>[]),
        detailBase is int
            ? detailBase
            : (op['base_version'] ?? op['observed_base_version']),
        detailServerVersion is int ? detailServerVersion : null,
        jsonEncode(detail?['server_value'] ?? <String, Object?>{}),
        jsonEncode(detail?['client_value'] ?? <String, Object?>{}),
        status,
        source,
        now,
        status == 'open' ? null : now,
      ],
    );
  }

  void _snapshot(
    String entityType,
    String entityId,
    Object? row,
    String source,
  ) {
    if (row is! Map) {
      return;
    }
    final version = row['version'];
    _raw.execute(
      'INSERT INTO sync_entity_snapshot (entity_type, entity_id, row_json, '
      'server_version, source, updated_at_utc) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (entity_type, entity_id) DO UPDATE SET '
      'row_json = excluded.row_json, server_version = excluded.server_version, '
      'source = excluded.source, updated_at_utc = excluded.updated_at_utc '
      'WHERE excluded.server_version >= sync_entity_snapshot.server_version',
      [
        entityType,
        entityId,
        jsonEncode(row),
        version is int ? version : 0,
        source,
        _iso(),
      ],
    );
  }

  // ------------------------------------------------------ recovery actions

  /// Recovery of a rejected operation by sending the entity's current local state
  /// as a **new** operation (new `operation_id`). The rejected operation stays as
  /// history and is marked handled. Returns the new operation id, or null when
  /// nothing differs from the last known server state.
  String? resubmitRejected(String operationId) {
    return _transaction(() {
      final op = _unhandled(operationId, 'rejected');
      return _resubmit(op);
    });
  }

  /// Recovery of a rejected operation by restoring the entity from the last known
  /// server snapshot. Pending, never-claimed operations of the entity are
  /// archived first; nothing is sent and nothing is deleted.
  void discardLocalAfterRejection(String operationId) {
    _transaction(() {
      final op = _unhandled(operationId, 'rejected');
      _restoreFromServer(op, 'discarded_local');
      _handle(op);
    });
  }

  /// Resolves an open conflict by taking the server's version: pending operations
  /// of the entity are archived, the entity is restored from the snapshot.
  void resolveConflictUseServer(String conflictId) {
    _transaction(() {
      final conflict = _conflictForAction(conflictId);
      final op = _opById(conflict['operation_id'] as String);
      _restoreFromServer(op, 'resolved_use_server');
      if (conflict['status'] == 'open') {
        _resolveMirror(conflictId, 'resolved_server', 'user_use_server');
      }
      _handle(op);
    });
  }

  /// Resolves an open conflict by sending the local state again as a new
  /// operation based on the server version recorded with the conflict. Returns
  /// the new operation id, or null when local and server already agree.
  String? resolveConflictRetryLocal(String conflictId) {
    return _transaction(() {
      final conflict = _conflictForAction(conflictId);
      final op = _opById(conflict['operation_id'] as String);
      final id = _resubmit(op);
      if (conflict['status'] == 'open') {
        _resolveMirror(conflictId, 'resolved_local', 'user_retry_local');
      }
      return id;
    });
  }

  Map<String, Object?> _unhandled(String operationId, String state) {
    final op = _opById(operationId);
    if (op['state'] != state || op['handled_at_utc'] != null) {
      throw RepositoryException(
        'operation $operationId is not an unhandled $state operation',
      );
    }
    return op;
  }

  Map<String, Object?> _opById(String operationId) {
    final rows = _rows('SELECT * FROM sync_outbox WHERE operation_id = ?', [
      operationId,
    ]);
    if (rows.isEmpty) {
      throw RepositoryException('unknown operation $operationId');
    }
    return rows.single;
  }

  /// A conflict whose local operation still needs a decision. The mirror may
  /// already be resolved (another device resolved it on the server): the local
  /// data still waits for the user.
  Map<String, Object?> _conflictForAction(String conflictId) {
    final rows = _rows('SELECT * FROM sync_conflicts_local WHERE id = ?', [
      conflictId,
    ]);
    if (rows.isEmpty) {
      throw RepositoryException('unknown conflict $conflictId');
    }
    final op = _opById(rows.single['operation_id'] as String);
    if (op['handled_at_utc'] != null) {
      throw RepositoryException('conflict $conflictId is already handled');
    }
    return rows.single;
  }

  void _handle(Map<String, Object?> op) {
    _raw.execute('UPDATE sync_outbox SET handled_at_utc = ? WHERE seq = ?', [
      _iso(),
      op['seq'],
    ]);
  }

  void _resolveMirror(String id, String status, String source) {
    _raw.execute(
      'UPDATE sync_conflicts_local SET status = ?, resolution_source = ?, '
      'resolved_at_utc = ? WHERE id = ?',
      [status, source, _iso(), id],
    );
  }

  /// The last server state this device knows for an entity (read-only; used to
  /// show the server's side of a conflict). Null when none was recorded.
  Map<String, Object?>? serverSnapshot(String entityType, String entityId) =>
      _snapshotRow(entityType, entityId);

  Map<String, Object?>? _snapshotRow(String entityType, String entityId) {
    final rows = _rows(
      'SELECT row_json, server_version FROM sync_entity_snapshot '
      'WHERE entity_type = ? AND entity_id = ?',
      [entityType, entityId],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = Map<String, Object?>.from(
      jsonDecode(rows.single['row_json'] as String) as Map,
    );
    row['version'] = rows.single['server_version'];
    return row;
  }

  Map<String, Object?> _localRow(String entityType, String entityId) {
    final rows = _rows('SELECT * FROM ${_table(entityType)} WHERE id = ?', [
      entityId,
    ]);
    if (rows.isEmpty) {
      throw RepositoryException('unknown $entityType $entityId');
    }
    return rows.single;
  }

  String? _resubmit(Map<String, Object?> op) {
    final entityType = op['entity_type'] as String;
    final entityId = op['entity_id'] as String;
    _handle(op);
    final local = _localRow(entityType, entityId);
    final snapshot = _snapshotRow(entityType, entityId);
    final opType = op['op_type'] as String;
    if (opType == 'create' && snapshot == null) {
      final patch = createPatchFromRow(entityType, local);
      final parentType = entityType == 'task'
          ? (local['parent_id'] != null ? 'task' : 'project')
          : null;
      final parentId = entityType == 'task'
          ? (local['parent_id'] ?? local['project_id']) as String?
          : null;
      final dependsOn = (parentType == null || parentId == null)
          ? null
          : _unfinishedCreateSeq(parentType, parentId);
      _insertOp(entityType, entityId, 'create', 0, patch, dependsOn);
      return _newestOperationId(entityType, entityId);
    }
    if (snapshot == null) {
      throw RepositoryException('no server snapshot for $entityType $entityId');
    }
    final observed = snapshot['version'] as int;
    if (opType == 'delete') {
      final tree = _treeIds(op['payload_json'] as String);
      if (tree != null) {
        final stillDeleted = [
          for (final id in tree)
            if (_rows(
              'SELECT 1 FROM tasks WHERE id = ? AND deleted_at IS NOT NULL',
              [id],
            ).isNotEmpty)
              id,
        ];
        _insertOp(entityType, entityId, 'delete', observed, {
          'tree': stillDeleted,
        }, null);
      } else {
        _insertOp(entityType, entityId, 'delete', observed, null, null);
      }
      return _newestOperationId(entityType, entityId);
    }
    final patch = changedFields(entityType, local, snapshot);
    if (patch.isEmpty) {
      return null;
    }
    _insertOp(entityType, entityId, 'update', observed, patch, null);
    return _newestOperationId(entityType, entityId);
  }

  String _newestOperationId(String entityType, String entityId) {
    return _latestOp(entityType, entityId)!['operation_id'] as String;
  }

  void _restoreFromServer(Map<String, Object?> op, String reason) {
    final entityType = op['entity_type'] as String;
    final entityId = op['entity_id'] as String;
    final snapshot = _snapshotRow(entityType, entityId);
    if (snapshot == null) {
      throw RepositoryException('no server snapshot for $entityType $entityId');
    }
    _archivePending(entityType, entityId, reason);
    final fields = entityType == 'project'
        ? projectUpdatableFields
        : taskUpdatableFields;
    final local = _localRow(entityType, entityId);
    final values = <Object?>[];
    final sets = <String>[];
    for (final field in [...fields, 'deleted_at']) {
      sets.add('$field = ?');
      // An older server answers no `due_time`: it has none, so neither do we.
      values.add(
        snapshot.containsKey(field) || field == 'due_time'
            ? serverColumnValue(field, snapshot)
            : local[field],
      );
    }
    // A tree delete that never reached the server: every listed entity is live
    // there, so the local tombstones go away together with the root's.
    final tree = _treeIds(op['payload_json'] as String);
    if (tree != null && op['op_type'] == 'delete') {
      for (final id in tree) {
        _raw.execute(
          'UPDATE tasks SET deleted_at = NULL, updated_at = ? WHERE id = ?',
          [_iso(), id],
        );
      }
    }
    _raw.execute(
      'UPDATE ${_table(entityType)} SET ${sets.join(', ')}, version = ?, '
      'updated_at = ? WHERE id = ?',
      [...values, snapshot['version'], _iso(), entityId],
    );
  }

  /// Moves the entity's never-claimed pending operations to the archive. Refuses
  /// when an operation is in flight or was claimed before: that work may already
  /// be on the server and must finish first.
  void _archivePending(String entityType, String entityId, String reason) {
    final busy = _rows(
      "SELECT 1 FROM sync_outbox WHERE entity_type = ? AND entity_id = ? "
      "AND (state = 'in_flight' OR (state = 'pending' AND base_version IS NOT NULL))",
      [entityType, entityId],
    );
    if (busy.isNotEmpty) {
      throw RepositoryException(
        '$entityType $entityId has operations in flight',
      );
    }
    for (final row in _rows(
      "SELECT * FROM sync_outbox WHERE entity_type = ? AND entity_id = ? AND state = 'pending'",
      [entityType, entityId],
    )) {
      _raw.execute(
        'INSERT INTO sync_outbox_archive (source, archive_reason, original_rowid, '
        'operation_id, entity_type, entity_id, operation_type, base_version, '
        'payload_json, created_at_utc, state, attempts, last_error, archived_at_utc) '
        "VALUES ('v2', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          reason,
          row['seq'],
          row['operation_id'],
          row['entity_type'],
          row['entity_id'],
          row['op_type'],
          row['base_version'],
          row['payload_json'],
          row['created_at_utc'],
          row['state'],
          row['attempts'],
          row['last_error'],
          _iso(),
        ],
      );
      _raw.execute('DELETE FROM sync_outbox WHERE seq = ?', [row['seq']]);
    }
  }

  // -------------------------------------------------- engine-facing actions

  /// Rejected `blocked_by_conflict` operations whose entity has no open conflict
  /// any more are resubmitted as new operations built from the current local state
  /// (nothing is discarded). Returns how many new operations were created.
  int resubmitBlocked() {
    return _transaction(() {
      var created = 0;
      final blocked = _rows(
        'SELECT o.operation_id FROM sync_outbox o '
        "WHERE o.state = 'rejected' AND o.error_code = 'blocked_by_conflict' AND o.handled_at_utc IS NULL "
        'AND NOT EXISTS (SELECT 1 FROM sync_conflicts_local c WHERE c.entity_type = o.entity_type '
        "AND c.entity_id = o.entity_id AND c.status = 'open') "
        'AND NOT EXISTS (SELECT 1 FROM sync_outbox x WHERE x.entity_type = o.entity_type '
        "AND x.entity_id = o.entity_id AND x.state = 'conflict' AND x.handled_at_utc IS NULL) "
        'ORDER BY o.seq',
      );
      for (final row in blocked) {
        if (_resubmit(_opById(row['operation_id'] as String)) != null) {
          created++;
        }
      }
      return created;
    });
  }

  /// Conflicts that need a decision: the local operation is unhandled.
  List<Map<String, Object?>> conflictsNeedingAction() {
    return _rows(
      'SELECT c.* FROM sync_conflicts_local c JOIN sync_outbox o ON o.operation_id = c.operation_id '
      "WHERE o.state = 'conflict' AND o.handled_at_utc IS NULL ORDER BY o.seq",
    );
  }

  /// Rejected operations nobody has handled yet.
  List<Map<String, Object?>> rejectedNeedingAction() {
    return _rows(
      "SELECT * FROM sync_outbox WHERE state = 'rejected' AND handled_at_utc IS NULL ORDER BY seq",
    );
  }

  /// Completes a conflict locally after the **server** accepted a resolution
  /// (`result` is the resolve RPC's applied result). Nothing is deleted: pending
  /// work of the entity is archived only when the server state replaces it.
  void applyServerResolution(String conflictId, Map<String, Object?> result) {
    final resolution = result['resolution'];
    final row = result['row'];
    if (result['status'] != 'applied' || resolution is! String || row is! Map) {
      throw const OutboxProtocolException('not an applied resolution result');
    }
    _transaction(() {
      final conflict = _conflictForAction(conflictId);
      final op = _opById(conflict['operation_id'] as String);
      final entityType = op['entity_type'] as String;
      final entityId = op['entity_id'] as String;
      final serverRow = Map<String, Object?>.from(row);
      switch (resolution) {
        case 'resolved_server':
          _snapshot(entityType, entityId, serverRow, 'ack');
          _restoreFromServer(op, 'resolved_use_server');
          _finishMirror(conflict, 'resolved_server', 'server_use_server');
        case 'resolved_client':
          _snapshot(entityType, entityId, serverRow, 'ack');
          _raiseVersion(entityType, entityId, serverRow);
          _finishMirror(conflict, 'resolved_local', 'server_keep_local');
        case 'resolved_merged':
          _snapshot(entityType, entityId, serverRow, 'ack');
          final fields = entityType == 'project'
              ? projectUpdatableFields
              : taskUpdatableFields;
          final sets = <String>[];
          final values = <Object?>[];
          for (final field in fields) {
            sets.add('$field = ?');
            values.add(serverColumnValue(field, serverRow));
          }
          _raw.execute(
            'UPDATE ${_table(entityType)} SET ${sets.join(', ')}, version = MAX(version, ?) WHERE id = ?',
            [...values, serverRow['version'], entityId],
          );
          _finishMirror(conflict, 'resolved_local', 'server_merged');
        case 'recreate_copy':
          // The original stays tombstoned (permanent); the copy arrives through
          // the pull applier. Pending work on the original is archived.
          _restoreFromServer(op, 'resolved_copy');
          _finishMirror(conflict, 'resolved_local', 'server_copy');
        default:
          throw const OutboxProtocolException('unknown resolution');
      }
      _handle(op);
    });
  }

  void _finishMirror(
    Map<String, Object?> conflict,
    String status,
    String source,
  ) {
    if (conflict['status'] == 'open') {
      _resolveMirror(conflict['id'] as String, status, source);
    }
  }

  void _raiseVersion(
    String entityType,
    String entityId,
    Map<String, Object?> serverRow,
  ) {
    final version = serverRow['version'];
    if (version is int) {
      _raw.execute(
        'UPDATE ${_table(entityType)} SET version = MAX(version, ?) WHERE id = ?',
        [version, entityId],
      );
    }
  }

  // -------------------------------------------------------------- sync state

  /// The device id, created once and persisted (`sync_state`).
  String deviceId() {
    return _transaction(() {
      _raw.execute('INSERT OR IGNORE INTO sync_state (singleton) VALUES (1)');
      final rows = _rows(
        'SELECT device_id FROM sync_state WHERE singleton = 1',
      );
      final existing = rows.single['device_id'] as String?;
      if (existing != null) {
        return existing;
      }
      final id = _ids.nextId();
      _raw.execute('UPDATE sync_state SET device_id = ? WHERE singleton = 1', [
        id,
      ]);
      return id;
    });
  }

  // ----------------------------------------------------------------- helpers

  String _table(String entityType) {
    return switch (entityType) {
      'project' => 'projects',
      'task' => 'tasks',
      _ => throw RepositoryException('unknown entity type $entityType'),
    };
  }

  String _iso() => _now().toUtc().toIso8601String();

  List<Map<String, Object?>> _rows(
    String sql, [
    List<Object?> params = const [],
  ]) {
    return [
      for (final row in _raw.select(sql, params))
        {for (final key in row.keys) key: row[key]},
    ];
  }

  T _transaction<T>(T Function() body) {
    _raw.execute('BEGIN IMMEDIATE;');
    try {
      final result = body();
      _raw.execute('COMMIT;');
      return result;
    } catch (_) {
      if (!_raw.autocommit) {
        _raw.execute('ROLLBACK;');
      }
      rethrow;
    }
  }
}
