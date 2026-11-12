import 'dart:convert';

import 'package:nexora/features/sync/sync_transport.dart';

/// A deterministic in-memory server that follows the S2/S3/S4 wire contract
/// closely enough to test the engine: idempotent push by `operation_id`,
/// field-level conflicts from server-owned `field_versions`, blocked operations,
/// atomic tree delete with a verified manifest, conflict resolution, device
/// revocation, and cursor pull over one stream shared by rows and conflicts
/// (cursor values have gaps, like the real server). One user, many devices.
final class FakeSyncServer implements SyncTransport {
  FakeSyncServer({this.userId = 'user-1'});

  final String userId;
  int seq = 0;
  final Map<String, bool> devices = {}; // device id -> revoked
  final Map<String, Map<String, Object?>> rows = {};
  final Map<String, Map<String, Object?>> stored = {}; // operation id -> result
  final Map<String, String> hashes = {};
  final Map<String, Map<String, Object?>> conflicts = {};
  final List<String> log = [];

  int _next() => ++seq;

  static const _projectFields = [
    'name',
    'description',
    'color',
    'is_archived',
    'sort_order',
  ];
  static const _taskFields = [
    'parent_id',
    'title',
    'notes',
    'status',
    'priority',
    'due_date',
    'completed_at',
    'sort_order',
  ];

  // ----------------------------------------------------------- test helpers

  Map<String, Object?>? row(String type, String id) => rows['$type:$id'];

  /// A change made by "another device" outside the protocol, with correct
  /// versioning (used to create concurrent edits).
  void otherDeviceEdit(String type, String id, Map<String, Object?> patch) {
    final r = rows['$type:$id']!;
    r['version'] = (r['version'] as int) + 1;
    final fv = Map<String, Object?>.from(r['field_versions'] as Map);
    for (final e in patch.entries) {
      r[e.key] = e.value;
      fv[e.key] = r['version'];
    }
    r['field_versions'] = fv;
    r['change_seq'] = _next();
  }

  void activeDevice(String id) => devices[id] = false;

  // -------------------------------------------------------------- transport

  void _device(String deviceId) {
    if (devices[deviceId] != false) {
      throw const SyncServerError('device_invalid');
    }
  }

  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) async {
    log.add('register');
    if (devices[deviceId] == true) {
      throw const SyncServerError('device_invalid');
    }
    final created = !devices.containsKey(deviceId);
    if (created && devices.values.where((revoked) => !revoked).length >= 10) {
      throw const SyncServerError('device_limit');
    }
    devices[deviceId] = false;
    return {
      'device_id': deviceId,
      'created': created,
      'active_devices': devices.values.where((r) => !r).length,
    };
  }

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) async {
    log.add('push:${operations.length}');
    _device(deviceId);
    if (operations.isEmpty) throw const SyncServerError('invalid_request');
    if (operations.length > 100) throw const SyncServerError('batch_too_large');
    return [for (final op in operations) _apply(op)];
  }

  Map<String, Object?> _apply(Map<String, Object?> op) {
    final opId = op['operation_id'] as String;
    final hash = jsonEncode([
      op['entity_type'],
      op['entity_id'],
      op['op_type'],
      op['base_version'],
      op['patch'],
    ]);
    final seen = stored[opId];
    if (seen != null) {
      if (hashes[opId] == hash) return {...seen, 'replayed': true};
      return {
        'operation_id': opId,
        'status': 'rejected',
        'error_code': 'operation_id_reuse',
        'replayed': false,
      };
    }
    final result = _applyNew(op, opId);
    _next(); // the operation record takes a sequence value too (gaps)
    stored[opId] = result;
    hashes[opId] = hash;
    return result;
  }

  Map<String, Object?> _rejected(String opId, String code) => {
    'operation_id': opId,
    'status': 'rejected',
    'error_code': code,
    'replayed': false,
  };

  Map<String, Object?> _applied(
    String opId,
    Map<String, Object?> r,
    int before,
  ) => {
    'operation_id': opId,
    'status': 'applied',
    'version_before': before,
    'applied_version': r['version'],
    'row': Map<String, Object?>.from(r),
    'replayed': false,
  };

  Map<String, Object?> _conflict(
    String opId,
    Map<String, Object?> op,
    String kind,
    List<String> fields,
    Map<String, Object?> serverValue,
    Map<String, Object?> clientValue,
    Map<String, Object?> r,
  ) {
    final id = 'c-$opId';
    conflicts[id] = {
      'id': id,
      'user_id': userId,
      'operation_id': opId,
      'kind': kind,
      'entity_type': op['entity_type'],
      'entity_id': op['entity_id'],
      'fields': fields,
      'base_version': op['base_version'] ?? 0,
      'server_version': r['version'],
      'server_value': serverValue,
      'client_value': clientValue,
      'status': 'open',
      'resolution_source': null,
      'created_at': '2026-11-12T10:00:00+00:00',
      'resolved_at': null,
      'change_seq': _next(),
    };
    return {
      'operation_id': opId,
      'status': 'conflict',
      'version_before': r['version'],
      'conflict_id': id,
      'row': Map<String, Object?>.from(r),
      'conflict': {
        'kind': kind,
        'fields': fields,
        'base_version': op['base_version'] ?? 0,
        'server_version': r['version'],
        'server_value': serverValue,
        'client_value': clientValue,
        'status': 'open',
      },
      'replayed': false,
    };
  }

  bool _hasOpenConflict(String type, String id) => conflicts.values.any(
    (c) =>
        c['entity_type'] == type &&
        c['entity_id'] == id &&
        c['status'] == 'open',
  );

  Map<String, Object?> _applyNew(Map<String, Object?> op, String opId) {
    final type = op['entity_type'] as String;
    final id = op['entity_id'] as String;
    final opType = op['op_type'] as String;
    final key = '$type:$id';
    if (_hasOpenConflict(type, id)) {
      return _rejected(opId, 'blocked_by_conflict');
    }
    final patch = Map<String, Object?>.from(
      (op['patch'] ?? <String, Object?>{}) as Map,
    );
    final allowed = type == 'project'
        ? _projectFields
        : [..._taskFields, if (opType == 'create') 'project_id'];
    if (opType == 'create') {
      if (patch.keys.any((k) => !allowed.contains(k))) {
        return _rejected(opId, 'invalid_patch');
      }
      final existing = rows[key];
      if (existing != null) {
        final differs = patch.entries.any((e) => existing[e.key] != e.value);
        if (existing['deleted_at'] == null && !differs) {
          return _applied(opId, existing, existing['version'] as int);
        }
        return _conflict(
          opId,
          op,
          'exists',
          patch.keys.toList()..sort(),
          {for (final k in patch.keys) k: existing[k]},
          patch,
          existing,
        );
      }
      if (type == 'task') {
        final project = rows['project:${patch['project_id']}'];
        if (project == null) return _rejected(opId, 'not_found');
        if (project['deleted_at'] != null) {
          return _rejected(opId, 'parent_invalid');
        }
        final parent = patch['parent_id'];
        if (parent != null) {
          final p = rows['task:$parent'];
          if (p == null ||
              p['deleted_at'] != null ||
              p['project_id'] != patch['project_id']) {
            return _rejected(opId, 'parent_invalid');
          }
        }
      }
      final r = <String, Object?>{
        'id': id,
        'owner_id': userId,
        ...(type == 'project'
            ? {
                'description': null,
                'color': null,
                'is_archived': false,
                'sort_order': 0,
                'name': null,
              }
            : {
                'parent_id': null,
                'notes': '',
                'status': 'open',
                'priority': 'none',
                'due_date': null,
                'completed_at': null,
                'sort_order': 0,
                'title': null,
                'project_id': null,
              }),
        ...patch,
        'version': 1,
        'field_versions': <String, Object?>{},
        'deleted_at': null,
        'change_seq': _next(),
        'created_at': '2026-11-12T10:00:00+00:00',
        'updated_at': '2026-11-12T10:00:00+00:00',
      };
      rows[key] = r;
      return _applied(opId, r, 0);
    }
    final r = rows[key];
    if (r == null) return _rejected(opId, 'not_found');
    final base = op['base_version'] as int?;
    if (base == null || base < 1 || base > (r['version'] as int)) {
      return _rejected(opId, 'invalid_op');
    }
    final before = r['version'] as int;
    if (opType == 'update') {
      if (patch.keys.any((k) => !allowed.contains(k))) {
        return _rejected(opId, 'invalid_patch');
      }
      if (r['deleted_at'] != null) {
        return _conflict(
          opId,
          op,
          'edit_deleted',
          patch.keys.toList()..sort(),
          {'deleted_at': r['deleted_at']},
          patch,
          r,
        );
      }
      final fv = Map<String, Object?>.from(r['field_versions'] as Map);
      final conflicting = <String>[];
      final changed = <String>[];
      for (final e in patch.entries) {
        if (r[e.key] == e.value) continue;
        if (((fv[e.key] as int?) ?? 0) > base) {
          conflicting.add(e.key);
        }
        else {
          changed.add(e.key);
        }
      }
      if (conflicting.isNotEmpty) {
        conflicting.sort();
        return _conflict(
          opId,
          op,
          'field',
          conflicting,
          {for (final k in conflicting) k: r[k]},
          {for (final k in conflicting) k: patch[k]},
          r,
        );
      }
      if (changed.isNotEmpty) {
        r['version'] = before + 1;
        for (final k in changed) {
          r[k] = patch[k];
          fv[k] = r['version'];
        }
        r['field_versions'] = fv;
        r['change_seq'] = _next();
      }
      return _applied(opId, r, before);
    }
    // delete
    if (r['deleted_at'] != null) return _applied(opId, r, before);
    final tree = patch['tree'];
    final descendants = _descendants(type, id);
    final live = descendants
        .where((d) => rows[d]!['deleted_at'] == null)
        .toList();
    if (tree is List) {
      final ids = [for (final e in tree) 'task:${(e as Map)['id']}'];
      if (ids.any((i) => !descendants.contains(i)) ||
          ids.toSet().length != ids.length) {
        return _rejected(opId, 'invalid_patch');
      }
      final missing = live.where((d) => !ids.contains(d)).toList();
      if (missing.isNotEmpty) {
        return _conflict(
          opId,
          op,
          'parent_has_live_children',
          ['deleted_at'],
          {
            'live_children': [for (final m in missing) m.substring(5)],
          },
          {'op': 'delete', 'tree': tree},
          r,
        );
      }
      if (base < before) {
        return _conflict(
          opId,
          op,
          'delete_edited',
          ['deleted_at'],
          {'version': before},
          {'op': 'delete', 'base_version': base, 'tree': tree},
          r,
        );
      }
      final edited = <Map<String, Object?>>[];
      for (final e in tree) {
        final m = e as Map;
        final d = rows['task:${m['id']}']!;
        if (d['deleted_at'] == null &&
            (d['version'] as int) > (m['base_version'] as int)) {
          edited.add({
            'id': m['id'],
            'version': d['version'],
            'base_version': m['base_version'],
          });
        }
      }
      if (edited.isNotEmpty) {
        return _conflict(
          opId,
          op,
          'delete_edited',
          ['deleted_at'],
          {'edited': edited},
          {'op': 'delete', 'base_version': base, 'tree': tree},
          r,
        );
      }
      for (final d in live) {
        _tombstone(rows[d]!);
      }
      _tombstone(r);
      return {..._applied(opId, r, before), 'tree_deleted': live.length + 1};
    }
    if (live.isNotEmpty) {
      return _conflict(
        opId,
        op,
        'parent_has_live_children',
        ['deleted_at'],
        {'live_children': true},
        {'op': 'delete'},
        r,
      );
    }
    if (before > base) {
      return _conflict(
        opId,
        op,
        'delete_edited',
        ['deleted_at'],
        {'version': before},
        {'op': 'delete', 'base_version': base},
        r,
      );
    }
    _tombstone(r);
    return _applied(opId, r, before);
  }

  void _tombstone(Map<String, Object?> r) {
    r['version'] = (r['version'] as int) + 1;
    r['deleted_at'] = '2026-11-12T11:00:00+00:00';
    final fv = Map<String, Object?>.from(r['field_versions'] as Map);
    fv['deleted_at'] = r['version'];
    r['field_versions'] = fv;
    r['change_seq'] = _next();
  }

  List<String> _descendants(String type, String id) {
    final out = <String>[];
    void walk(String parent) {
      for (final e in rows.entries) {
        if (e.key.startsWith('task:') &&
            e.value['parent_id'] == parent &&
            !out.contains(e.key)) {
          out.add(e.key);
          walk(e.key.substring(5));
        }
      }
    }

    if (type == 'project') {
      for (final e in rows.entries) {
        if (e.key.startsWith('task:') && e.value['project_id'] == id) {
          out.add(e.key);
        }
      }
    } else {
      walk(id);
    }
    return out;
  }

  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) async {
    log.add('pull:$cursor');
    _device(deviceId);
    if (cursor < 0 || cursor > seq) {
      throw const SyncServerError('invalid_cursor');
    }
    final items = <MapEntry<int, Map<String, Object?>>>[
      for (final e in rows.entries)
        if ((e.value['change_seq'] as int) > cursor)
          MapEntry(e.value['change_seq'] as int, {
            'entity_type': e.key.split(':').first,
            'row': Map<String, Object?>.from(e.value),
          }),
      for (final c in conflicts.values)
        if ((c['change_seq'] as int) > cursor)
          MapEntry(c['change_seq'] as int, {
            'conflict': Map<String, Object?>.from(c),
          }),
    ]..sort((a, b) => a.key.compareTo(b.key));
    final page = items.take(limit).toList();
    return {
      'changes': [
        for (final i in page)
          if (i.value.containsKey('row')) i.value,
      ],
      'conflicts': [
        for (final i in page)
          if (i.value.containsKey('conflict')) i.value['conflict'],
      ],
      'next_cursor': page.isEmpty ? cursor : page.last.key,
      'has_more': items.length > page.length,
    };
  }

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) async {
    log.add('resolve:$resolution');
    _device(deviceId);
    final seen = stored[operationId];
    if (seen != null) return {...seen, 'replayed': true};
    final c = conflicts[conflictId];
    if (c == null) return _rejected(operationId, 'not_found');
    if (c['status'] != 'open') {
      return _rejected(operationId, 'conflict_not_open');
    }
    final type = c['entity_type'] as String;
    final id = c['entity_id'] as String;
    final r = rows['$type:$id']!;
    final before = r['version'] as int;
    final clientValue = Map<String, Object?>.from(c['client_value'] as Map);
    final deleted = r['deleted_at'] != null;
    String status;
    String? copyId;
    switch (resolution) {
      case 'resolved_server':
        status = 'resolved_server';
      case 'resolved_client':
        if (clientValue.containsKey('tree') ||
            deleted ||
            c['kind'] == 'edit_deleted') {
          return _rejected(operationId, 'strategy_not_allowed');
        }
        if (c['kind'] == 'delete_edited' ||
            c['kind'] == 'parent_has_live_children') {
          _tombstone(r);
        } else {
          _edit(r, clientValue);
        }
        status = 'resolved_client';
      case 'resolved_merged':
        if (values == null || values.isEmpty || deleted) {
          return _rejected(operationId, 'invalid_values');
        }
        _edit(r, values);
        status = 'resolved_merged';
      case 'recreate_copy':
        if (!deleted) return _rejected(operationId, 'strategy_not_allowed');
        copyId = (values?['new_entity_id']) as String?;
        if (copyId == null || rows.containsKey('$type:$copyId')) {
          return _rejected(operationId, 'invalid_values');
        }
        final copy = Map<String, Object?>.from(r)
          ..addAll(clientValue)
          ..['id'] = copyId
          ..['version'] = 1
          ..['field_versions'] = <String, Object?>{}
          ..['deleted_at'] = null
          ..['change_seq'] = _next();
        rows['$type:$copyId'] = copy;
        status = 'resolved_copy';
      default:
        return _rejected(operationId, 'invalid_request');
    }
    c['status'] = status;
    c['resolution_source'] = 'user';
    c['resolved_at'] = '2026-11-12T12:00:00+00:00';
    c['change_seq'] = _next();
    final result = <String, Object?>{
      'operation_id': operationId,
      'status': 'applied',
      'conflict_id': conflictId,
      'resolution': resolution,
      'version_before': before,
      'row': Map<String, Object?>.from(
        copyId != null ? rows['$type:$copyId']! : r,
      ),
      'replayed': false,
      'copy_entity_id': ?copyId,
      if ((r['version'] as int) != before) 'applied_version': r['version'],
    };
    stored[operationId] = result;
    return result;
  }

  void _edit(Map<String, Object?> r, Map<String, Object?> patch) {
    r['version'] = (r['version'] as int) + 1;
    final fv = Map<String, Object?>.from(r['field_versions'] as Map);
    for (final e in patch.entries) {
      r[e.key] = e.value;
      fv[e.key] = r['version'];
    }
    r['field_versions'] = fv;
    r['change_seq'] = _next();
  }

  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) async {
    log.add('revoke');
    _device(deviceId);
    if (!devices.containsKey(targetDeviceId)) {
      throw const SyncServerError('device_invalid');
    }
    final newly = devices[targetDeviceId] == false;
    devices[targetDeviceId] = true;
    return {
      'device_id': targetDeviceId,
      'revoked': newly,
      'active_devices': devices.values.where((r) => !r).length,
    };
  }
}

/// A transport that injects scripted failures in front of (or just after) the
/// real call, for network-loss and authentication tests.
final class FaultyTransport implements SyncTransport {
  FaultyTransport(this.inner);

  final SyncTransport inner;

  /// One entry per upcoming `push`: null = pass through; otherwise the fault.
  final List<PushFault?> pushFaults = [];
  final List<SyncTransportException?> pullFaults = [];
  Future<void> Function(String call)? before;

  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) async {
    await before?.call('register');
    return inner.registerDevice(deviceId, label: label);
  }

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) async {
    await before?.call('push');
    final fault = pushFaults.isEmpty ? null : pushFaults.removeAt(0);
    if (fault == null) return inner.push(deviceId, operations);
    if (fault.afterCommit) {
      await inner.push(
        deviceId,
        operations,
      ); // the server committed; the response is lost
    }
    throw fault.error;
  }

  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) async {
    await before?.call('pull');
    final fault = pullFaults.isEmpty ? null : pullFaults.removeAt(0);
    if (fault != null) throw fault;
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
    await before?.call('resolve');
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
    await before?.call('revoke');
    return inner.revokeDevice(deviceId, targetDeviceId);
  }
}

final class PushFault {
  const PushFault(this.error, {this.afterCommit = false});

  final SyncTransportException error;

  /// The server applied the batch before the failure (the response was lost).
  final bool afterCommit;
}
