import 'dart:convert';

import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:sqlite3/sqlite3.dart';

import 'entity_patch.dart';
import 'local_database.dart';
import 'server_row.dart';

/// The server answered a pull in a shape the client cannot trust. Nothing is
/// applied and the cursor does not move; the caller retries.
final class PullProtocolException implements Exception {
  const PullProtocolException(this.message);

  final String message;

  @override
  String toString() => 'PullProtocolException: $message';
}

/// What applying one page did.
final class PullResult {
  const PullResult({
    required this.applied,
    required this.preserved,
    required this.skippedLocal,
    required this.staged,
    required this.conflicts,
    required this.nextCursor,
    required this.hasMore,
  });

  /// Rows written to the local file (fully or with pending fields preserved).
  final int applied;

  /// Of those, rows where at least one field kept its local, not yet sent value.
  final int preserved;

  /// Server rows that match a local-only or unclassified row: never touched.
  final int skippedLocal;

  /// Rows waiting for a parent that has not arrived.
  final int staged;

  /// Conflict records mirrored or updated.
  final int conflicts;
  final int nextCursor;
  final bool hasMore;
}

enum _Outcome { applied, appliedPreserving, skippedLocal, missingParent }

final class _Incoming {
  const _Incoming(this.type, this.id, this.row, this.seq);

  final String type;
  final String id;
  final Map<String, Object?> row;
  final int seq;
}

/// Applies pulled pages to the local file.
///
/// One page is one transaction together with the cursor advance (all or nothing).
/// A pulled row never overwrites a field that has a pending, in-flight, conflicted
/// or rejected local operation; those fields keep their local value until the
/// operation is resolved. Rows of local-only and unclassified entities are never
/// written. A row whose project or parent has not arrived yet waits in
/// `sync_pull_stage` and is applied when its parent exists.
final class PullApplier {
  PullApplier(this._db, {DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  final LocalDatabase _db;
  final DateTime Function() _now;

  Database get _raw => _db.raw;

  /// Applies one response of `nexora_sync_pull` and advances the cursor.
  PullResult applyPage(Map<String, Object?> response) {
    final changes = response['changes'];
    final conflicts = response['conflicts'];
    final next = response['next_cursor'];
    final more = response['has_more'];
    if (changes is! List ||
        conflicts is! List ||
        next is! int ||
        more is! bool) {
      throw const PullProtocolException('malformed pull response');
    }
    final fresh = <_Incoming>[];
    for (final change in changes) {
      if (change is! Map) {
        throw const PullProtocolException('a change is not an object');
      }
      final type = change['entity_type'];
      final row = change['row'];
      if ((type != 'project' && type != 'task') || row is! Map) {
        throw const PullProtocolException('a change has no entity or row');
      }
      final id = row['id'];
      final version = row['version'];
      final seq = row['change_seq'];
      if (id is! String || version is! int || seq is! int) {
        throw const PullProtocolException(
          'a row lacks id, version or change_seq',
        );
      }
      fresh.add(
        _Incoming(type as String, id, Map<String, Object?>.from(row), seq),
      );
    }
    for (final conflict in conflicts) {
      if (conflict is! Map || conflict['id'] is! String) {
        throw const PullProtocolException('a conflict has no id');
      }
    }
    return _transaction(() {
      final incoming = <String, _Incoming>{};
      for (final row in _raw.select(
        'SELECT entity_type, entity_id, row_json, server_seq FROM sync_pull_stage',
      )) {
        final item = _Incoming(
          row['entity_type'] as String,
          row['entity_id'] as String,
          Map<String, Object?>.from(
            jsonDecode(row['row_json'] as String) as Map,
          ),
          row['server_seq'] as int,
        );
        incoming['${item.type}:${item.id}'] = item;
      }
      for (final item in fresh) {
        final key = '${item.type}:${item.id}';
        final old = incoming[key];
        if (old == null || item.seq >= old.seq) {
          incoming[key] = item;
        }
      }
      var remaining = incoming.values.toList()
        ..sort((a, b) {
          final byType =
              (a.type == 'project' ? 0 : 1) - (b.type == 'project' ? 0 : 1);
          return byType != 0 ? byType : a.seq.compareTo(b.seq);
        });
      var applied = 0;
      var preserved = 0;
      var skipped = 0;
      var progress = true;
      while (progress && remaining.isNotEmpty) {
        progress = false;
        final waiting = <_Incoming>[];
        for (final item in remaining) {
          switch (_applyOne(item)) {
            case _Outcome.applied:
              applied++;
              progress = true;
            case _Outcome.appliedPreserving:
              applied++;
              preserved++;
              progress = true;
            case _Outcome.skippedLocal:
              skipped++;
              progress = true;
            case _Outcome.missingParent:
              waiting.add(item);
          }
        }
        remaining = waiting;
      }
      _raw.execute('DELETE FROM sync_pull_stage');
      for (final item in remaining) {
        _raw.execute(
          'INSERT INTO sync_pull_stage (entity_type, entity_id, row_json, server_seq, staged_at_utc) '
          'VALUES (?, ?, ?, ?, ?)',
          [item.type, item.id, jsonEncode(item.row), item.seq, _iso()],
        );
      }
      var mirrored = 0;
      for (final conflict in conflicts) {
        _mirrorConflict(Map<String, Object?>.from(conflict as Map));
        mirrored++;
      }
      _raw.execute('INSERT OR IGNORE INTO sync_state (singleton) VALUES (1)');
      _raw.execute('UPDATE sync_state SET cursor = ? WHERE singleton = 1', [
        next,
      ]);
      return PullResult(
        applied: applied,
        preserved: preserved,
        skippedLocal: skipped,
        staged: remaining.length,
        conflicts: mirrored,
        nextCursor: next,
        hasMore: more,
      );
    });
  }

  /// Applies a single authoritative server row (for example the copy created by a
  /// "recreate as copy" resolution) with the same rules as a pulled row.
  void applyServerRow(String entityType, Map<String, Object?> row) {
    final id = row['id'];
    final version = row['version'];
    if (id is! String || version is! int) {
      throw const PullProtocolException('a row lacks id or version');
    }
    _transaction(() {
      final outcome = _applyOne(
        _Incoming(entityType, id, row, (row['change_seq'] as int?) ?? 0),
      );
      if (outcome == _Outcome.missingParent) {
        throw const RepositoryException(
          'the parent of the server row is not present locally',
        );
      }
    });
  }

  // ------------------------------------------------------------- one row

  _Outcome _applyOne(_Incoming item) {
    final table = item.type == 'project' ? 'projects' : 'tasks';
    final row = item.row;
    final version = row['version'] as int;
    if (item.type == 'task') {
      final projectId = row['project_id'];
      if (projectId is! String || !_exists('projects', projectId)) {
        return _Outcome.missingParent;
      }
      final parentId = row['parent_id'];
      if (parentId is String && !_exists('tasks', parentId)) {
        return _Outcome.missingParent;
      }
    }
    final local = _raw.select('SELECT * FROM $table WHERE id = ?', [item.id]);
    if (local.isEmpty) {
      _insert(item);
      _snapshot(item);
      return _Outcome.applied;
    }
    if (local.single['sync_scope'] != 'synced') {
      return _Outcome
          .skippedLocal; // never reclassify or overwrite local-only data
    }
    final pending = _pendingFields(item.type, item.id);
    final serverDeleted = row['deleted_at'] != null;
    if (serverDeleted && pending.any) {
      // The server tombstoned it while local work is still unsent: keep the local
      // row as it is; the push will surface the conflict.
      _raw.execute('UPDATE $table SET version = MAX(version, ?) WHERE id = ?', [
        version,
        item.id,
      ]);
      _snapshot(item);
      return _Outcome.appliedPreserving;
    }
    final fields = item.type == 'project'
        ? projectUpdatableFields
        : taskUpdatableFields;
    final sets = <String>[];
    final values = <Object?>[];
    var preserved = false;
    // The date and the time are one unit: a pending local edit of either keeps
    // both, so a pulled row can never leave a time without its date.
    final held = {...pending.fields};
    if (held.contains('due_date') || held.contains('due_time')) {
      held.addAll(const ['due_date', 'due_time']);
    }
    for (final field in [...fields, 'deleted_at']) {
      if (held.contains(field)) {
        preserved = true;
        continue;
      }
      sets.add('$field = ?');
      values.add(_columnValue(field, row));
    }
    sets.add('version = MAX(version, ?)');
    values.add(version);
    sets.add('updated_at = ?');
    values.add(_timestamp(row['updated_at']) ?? _iso());
    _raw.execute('UPDATE $table SET ${sets.join(', ')} WHERE id = ?', [
      ...values,
      item.id,
    ]);
    _snapshot(item);
    return preserved ? _Outcome.appliedPreserving : _Outcome.applied;
  }

  bool _exists(String table, String id) {
    return _raw.select('SELECT 1 FROM $table WHERE id = ?', [id]).isNotEmpty;
  }

  void _insert(_Incoming item) {
    final row = item.row;
    final owner = _localUser() ?? (row['owner_id'] as String? ?? 'unknown');
    final now = _iso();
    if (item.type == 'project') {
      _raw.execute(
        'INSERT INTO projects (id, owner_id, name, sort_order, version, sync_scope, '
        "deleted_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?, 'synced', ?, ?, ?)",
        [
          item.id,
          owner,
          row['name'],
          _columnValue('sort_order', row),
          row['version'],
          _columnValue('deleted_at', row),
          _timestamp(row['created_at']) ?? now,
          _timestamp(row['updated_at']) ?? now,
        ],
      );
      return;
    }
    _raw.execute(
      'INSERT INTO tasks (id, project_id, owner_id, parent_id, title, notes, status, priority, '
      'due_date, due_time, completed_at, sort_order, version, sync_scope, deleted_at, created_at, updated_at) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?, ?)",
      [
        item.id,
        row['project_id'],
        owner,
        row['parent_id'],
        row['title'],
        _columnValue('notes', row),
        row['status'],
        row['priority'],
        row['due_date'],
        // `17:30:00` from PostgreSQL becomes `17:30`; an older server has no key.
        row['due_date'] == null ? null : _columnValue('due_time', row),
        _columnValue('completed_at', row),
        _columnValue('sort_order', row),
        row['version'],
        _columnValue('deleted_at', row),
        _timestamp(row['created_at']) ?? now,
        _timestamp(row['updated_at']) ?? now,
      ],
    );
  }

  String? _localUser() {
    final rows = _raw.select("SELECT value FROM meta WHERE key = 'user_id'");
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Object? _columnValue(String field, Map<String, Object?> row) =>
      serverColumnValue(field, row);

  String? _timestamp(Object? value) => normalizeServerTimestamp(value);

  _Pending _pendingFields(String type, String id) {
    final fields = <String>{};
    var any = false;
    for (final op in _raw.select(
      'SELECT op_type, payload_json FROM sync_outbox WHERE entity_type = ? AND entity_id = ? '
      "AND (state IN ('pending', 'in_flight') OR (state IN ('conflict', 'rejected') AND handled_at_utc IS NULL))",
      [type, id],
    )) {
      any = true;
      final opType = op['op_type'] as String;
      if (opType == 'delete') {
        fields.add('deleted_at');
      } else if (opType == 'create') {
        fields.addAll(
          type == 'project' ? projectUpdatableFields : taskUpdatableFields,
        );
      } else {
        final decoded = jsonDecode(op['payload_json'] as String);
        if (decoded is Map) {
          fields.addAll(decoded.keys.cast<String>());
        }
      }
    }
    return _Pending(fields, any);
  }

  void _snapshot(_Incoming item) {
    _raw.execute(
      'INSERT INTO sync_entity_snapshot (entity_type, entity_id, row_json, server_version, source, updated_at_utc) '
      "VALUES (?, ?, ?, ?, 'pull', ?) "
      'ON CONFLICT (entity_type, entity_id) DO UPDATE SET row_json = excluded.row_json, '
      'server_version = excluded.server_version, source = excluded.source, updated_at_utc = excluded.updated_at_utc '
      'WHERE excluded.server_version >= sync_entity_snapshot.server_version',
      [item.type, item.id, jsonEncode(item.row), item.row['version'], _iso()],
    );
  }

  // ----------------------------------------------------------- conflicts

  void _mirrorConflict(Map<String, Object?> c) {
    final id = c['id'] as String;
    final serverStatus = c['status'] as String? ?? 'open';
    final localStatus = switch (serverStatus) {
      'open' => 'open',
      'resolved_server' => 'resolved_server',
      _ => 'resolved_local',
    };
    final existing = _raw.select(
      'SELECT status FROM sync_conflicts_local WHERE id = ?',
      [id],
    );
    final source = (c['resolution_source'] as String?) ?? 'server';
    if (existing.isEmpty) {
      final kind = c['kind'];
      final now = _iso();
      _raw.execute(
        'INSERT INTO sync_conflicts_local (id, operation_id, entity_type, entity_id, kind, fields_json, '
        'base_version, server_version, server_value_json, client_value_json, status, resolution_source, '
        'created_at_utc, resolved_at_utc) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          id,
          c['operation_id'],
          c['entity_type'],
          c['entity_id'],
          conflictKinds.contains(kind) ? kind : 'field',
          jsonEncode(c['fields'] ?? <Object?>[]),
          c['base_version'] is int ? c['base_version'] : 0,
          c['server_version'] is int ? c['server_version'] : null,
          jsonEncode(c['server_value'] ?? <String, Object?>{}),
          jsonEncode(c['client_value'] ?? <String, Object?>{}),
          localStatus,
          localStatus == 'open' ? null : source,
          _timestamp(c['created_at']) ?? now,
          localStatus == 'open' ? null : (_timestamp(c['resolved_at']) ?? now),
        ],
      );
      return;
    }
    if (existing.single['status'] == 'open' && localStatus != 'open') {
      _raw.execute(
        'UPDATE sync_conflicts_local SET status = ?, resolution_source = ?, resolved_at_utc = ? WHERE id = ?',
        [localStatus, source, _timestamp(c['resolved_at']) ?? _iso(), id],
      );
    }
  }

  // -------------------------------------------------------------- helpers

  String _iso() => _now().toUtc().toIso8601String();

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

final class _Pending {
  const _Pending(this.fields, this.any);

  final Set<String> fields;
  final bool any;
}
