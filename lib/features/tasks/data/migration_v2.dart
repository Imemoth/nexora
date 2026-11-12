import 'dart:convert';
import 'dart:io';

import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:sqlite3/sqlite3.dart';

import 'entity_patch.dart';
import 'schema_v2.dart';
import 'snapshot_digest.dart';

/// Called at named points of the migration. A test throws from it to prove that
/// a failure at that point rolls everything back.
typedef MigrationStepHook = void Function(String step);

/// What a migration did. Contains ids and counts only, never titles or notes.
final class MigrationReport {
  const MigrationReport({
    required this.fromVersion,
    required this.toVersion,
    required this.backupFile,
    required this.digestBefore,
    required this.counts,
    required this.warnings,
  });

  final int fromVersion;
  final int toVersion;

  /// The verified backup, or null when the file was new and held no data.
  final String? backupFile;
  final String digestBefore;
  final Map<String, int> counts;

  /// Codes such as `W05:task:<id>`.
  final List<String> warnings;
}

/// Schema migration 1 to 2 (Phase 3 S5), forward-only.
///
/// Order, all under one write lock (`BEGIN IMMEDIATE`, foreign keys off):
/// checks, snapshot digest, verified backup, classification, table rebuild,
/// outbox migration, triggers, post-checks, `user_version = 2`, `COMMIT`. Any
/// failure before `COMMIT` rolls back and leaves the file at version 1; the
/// backup is kept. A backup is never deleted or overwritten.
///
/// Entity classes (docs/coordination/phase-3-s5-outbox-v2.md section 5):
/// class S (synchronized): only pending base-0 upserts, no other state, no
/// delete, parent and project also class S. Its version becomes 0 because no
/// shipped build ever transmitted anything. Class U (unclassified): everything
/// else. It keeps its version, gets no operation and never synchronizes. Every
/// v1 operation is kept verbatim in `sync_outbox_archive`, in v1 `rowid` order.
final class MigrationV2 {
  MigrationV2(
    this._raw,
    this._path, {
    MigrationStepHook? onStep,
    String? backupDirectory,
    DateTime Function()? now,
  }) : _onStep = onStep,
       _backupDirectory = backupDirectory,
       _now = now ?? (() => DateTime.now().toUtc());

  final Database _raw;
  final String _path;
  final MigrationStepHook? _onStep;
  final String? _backupDirectory;
  final DateTime Function() _now;

  /// Runs the migration. [createBackup] is false only for a file that was just
  /// created and holds no user data.
  MigrationReport run({required bool createBackup}) {
    _raw.execute('PRAGMA foreign_keys = OFF;');
    _raw.execute('BEGIN IMMEDIATE;');
    var committed = false;
    try {
      _step('locked');
      _precheck();
      _step('prechecked');
      final digest = snapshotDigest(_raw);
      String? backup;
      if (createBackup) {
        backup = _backup(digest);
      }
      _step('backup_done');
      final v1 = _readV1();
      final plan = _classify(v1);
      _step('classified');
      final counts = _apply(v1, plan);
      _step('applied');
      final report = MigrationReport(
        fromVersion: 1,
        toVersion: 2,
        backupFile: backup,
        digestBefore: digest,
        counts: counts,
        warnings: plan.warnings,
      );
      _writeReport(report);
      _raw.userVersion = 2;
      _step('before_commit');
      _raw.execute('COMMIT;');
      committed = true;
      _raw.execute('PRAGMA foreign_keys = ON;');
      _postCommit();
      return report;
    } catch (_) {
      if (!committed && !_raw.autocommit) {
        _raw.execute('ROLLBACK;');
      }
      _raw.execute('PRAGMA foreign_keys = ON;');
      rethrow;
    }
  }

  void _step(String name) {
    final hook = _onStep;
    if (hook != null) {
      hook(name);
    }
  }

  Never _abort(String code) {
    throw RepositoryException('migration aborted: $code');
  }

  // ------------------------------------------------------------ pre-checks

  void _precheck() {
    if (_raw.userVersion != 1) {
      _abort('unexpected_version');
    }
    final integrity = _raw.select('PRAGMA integrity_check');
    if (integrity.isEmpty || integrity.first.values.first != 'ok') {
      _abort('integrity_check_failed');
    }
    if (_raw.select('PRAGMA foreign_key_check').isNotEmpty) {
      _abort('foreign_key_violation');
    }
    final longTitles = _raw.select(
      'SELECT COUNT(*) AS n FROM tasks WHERE length(trim(title)) > 200',
    );
    if ((longTitles.single['n'] as int) > 0) {
      _abort('title_too_long');
    }
    _boundUser();
  }

  /// The single owner of the file, or null for an empty file. Aborts when the
  /// rows or `meta` name more than one owner.
  String? _boundUser() {
    final owners = <String>{
      for (final row in _raw.select(
        'SELECT owner_id FROM projects UNION SELECT owner_id FROM tasks',
      ))
        row['owner_id'] as String,
    };
    if (owners.length > 1) {
      _abort('binding_mismatch');
    }
    final fromRows = owners.isEmpty ? null : owners.first;
    final metaOwner = _meta('owner_id');
    final metaUser = _meta('user_id');
    if (metaOwner != null && fromRows != null && metaOwner != fromRows) {
      _abort('binding_mismatch');
    }
    final user = metaOwner ?? fromRows;
    if (metaUser != null && user != null && metaUser != user) {
      _abort('binding_mismatch');
    }
    return metaUser ?? user;
  }

  String? _meta(String key) {
    final rows = _raw.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  // ---------------------------------------------------------------- backup

  /// Copies the locked snapshot with `VACUUM INTO` on a second connection (the
  /// first holds the write lock and has changed nothing yet), verifies the copy
  /// against the digest taken under the lock, and only then gives it its final
  /// name. Returns the final path. Never overwrites or deletes a file.
  String _backup(String digest) {
    final partial = _uniquePath('partial');
    try {
      final other = sqlite3.open(_path);
      try {
        other.execute('PRAGMA busy_timeout = 5000;');
        other.execute('VACUUM INTO ?', [partial]);
      } finally {
        other.close();
      }
    } on SqliteException {
      _keepAsFailed(partial);
      _abort('backup_failed');
    }
    var ok = false;
    try {
      final copy = sqlite3.open(partial, mode: OpenMode.readOnly);
      try {
        final quick = copy.select('PRAGMA quick_check');
        ok =
            quick.isNotEmpty &&
            quick.first.values.first == 'ok' &&
            copy.userVersion == 1 &&
            snapshotDigest(copy) == digest;
      } finally {
        copy.close();
      }
    } on SqliteException {
      ok = false;
    }
    if (!ok) {
      _keepAsFailed(partial);
      _abort('backup_verification_failed');
    }
    final finalPath = _uniquePath('bak');
    File(partial).renameSync(finalPath);
    return finalPath;
  }

  void _keepAsFailed(String partial) {
    final file = File(partial);
    if (file.existsSync()) {
      file.renameSync(_uniquePath('failed'));
    }
  }

  String _uniquePath(String extension) {
    final directory = _backupDirectory;
    final name = File(_path).uri.pathSegments.last;
    final base = directory == null
        ? '$_path.pre-v2'
        : '$directory${Platform.pathSeparator}$name.pre-v2';
    var candidate = '$base.$extension';
    var index = 1;
    while (File(candidate).existsSync()) {
      candidate = '$base.$index.$extension';
      index++;
    }
    return candidate;
  }

  // ---------------------------------------------------------- read and plan

  _V1Data _readV1() {
    final ops = <_V1Op>[];
    for (final row in _raw.select(
      'SELECT rowid AS rid, operation_id, entity_type, entity_id, operation_type, '
      'base_version, payload_json, created_at_utc, state, attempts, last_error '
      'FROM sync_outbox ORDER BY rowid',
    )) {
      ops.add(
        _V1Op(
          rowid: row['rid'] as int,
          operationId: row['operation_id'] as String,
          entityType: row['entity_type'] as String,
          entityId: row['entity_id'] as String,
          operationType: row['operation_type'] as String,
          baseVersion: row['base_version'] as int,
          payloadJson: row['payload_json'] as String,
          createdAt: row['created_at_utc'] as String,
          state: row['state'] as String,
          attempts: row['attempts'] as int,
          lastError: row['last_error'] as String?,
        ),
      );
    }
    final projects = <String, Map<String, Object?>>{};
    for (final row in _raw.select(
      'SELECT id, name, sort_order, deleted_at FROM projects',
    )) {
      projects[row['id'] as String] = {
        for (final key in row.keys) key: row[key],
      };
    }
    final tasks = <String, Map<String, Object?>>{};
    for (final row in _raw.select(
      'SELECT id, project_id, parent_id, title, notes, status, priority, '
      'due_date, completed_at, sort_order, deleted_at FROM tasks',
    )) {
      tasks[row['id'] as String] = {for (final key in row.keys) key: row[key]};
    }
    return _V1Data(ops, projects, tasks);
  }

  _Plan _classify(_V1Data v1) {
    final plan = _Plan();
    final groups = <String, List<_V1Op>>{};
    for (final op in v1.ops) {
      groups.putIfAbsent('${op.entityType}:${op.entityId}', () => []).add(op);
    }
    // Candidate entities for class S, with the create payload they would send.
    for (final entry in groups.entries) {
      final ops = entry.value;
      final type = ops.first.entityType;
      final id = ops.first.entityId;
      final row = type == 'project' ? v1.projects[id] : v1.tasks[id];
      if (row == null) {
        continue; // orphan operations are only archived
      }
      final simple = ops.every(
        (op) =>
            op.state == 'pending' &&
            op.baseVersion == 0 &&
            op.operationType == 'upsert',
      );
      if (!simple || row['deleted_at'] != null) {
        continue;
      }
      final patch = createPatchFromRow(type, row);
      final differs = _payloadDiffers(type, row, ops.last.payloadJson);
      if (differs == null) {
        plan.warnings.add('W07:$type:$id');
        continue;
      }
      if (differs) {
        plan.warnings.add('W05:$type:$id');
        continue;
      }
      if (utf8.encode(jsonEncode(patch)).length > maxPayloadBytes) {
        plan.warnings.add('W06:$type:$id');
        continue;
      }
      plan.createPatch[entry.key] = patch;
      plan.createOp[entry.key] = ops.first;
    }
    // A task is class S only if its project and parent are class S as well.
    var changed = true;
    while (changed) {
      changed = false;
      for (final key in plan.createPatch.keys.toList()) {
        if (!key.startsWith('task:')) {
          continue;
        }
        final task = v1.tasks[key.substring(5)]!;
        final projectOk = plan.createPatch.containsKey(
          'project:${task['project_id']}',
        );
        final parentId = task['parent_id'] as String?;
        final parentOk =
            parentId == null || plan.createPatch.containsKey('task:$parentId');
        if (!projectOk || !parentOk) {
          plan.createPatch.remove(key);
          plan.createOp.remove(key);
          plan.warnings.add('W08:$key');
          changed = true;
        }
      }
    }
    for (final op in v1.ops) {
      final key = '${op.entityType}:${op.entityId}';
      final exists = op.entityType == 'project'
          ? v1.projects.containsKey(op.entityId)
          : v1.tasks.containsKey(op.entityId);
      if (!exists) {
        plan.reason[op.rowid] = 'orphan_entity';
      } else if (plan.createOp[key] == null) {
        plan.reason[op.rowid] = 'unclassified_entity';
      } else if (identical(plan.createOp[key], op)) {
        plan.reason[op.rowid] = 'migrated_to_v2_create';
      } else {
        plan.reason[op.rowid] = 'folded_into_create';
      }
    }
    return plan;
  }

  /// Whether the last unsent payload differs from the stored row. Null when the
  /// payload cannot be read.
  bool? _payloadDiffers(String type, Map<String, Object?> row, String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) {
      return null;
    }
    final fields = type == 'project'
        ? const ['name', 'sort_order']
        : const [
            'project_id',
            'parent_id',
            'title',
            'notes',
            'status',
            'priority',
            'due_date',
            'sort_order',
          ];
    for (final field in fields) {
      Object? stored = row[field];
      Object? sent = decoded[field];
      if (field == 'notes') {
        stored = stored ?? '';
        sent = sent ?? '';
      }
      if (stored != sent) {
        return true;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------- apply

  Map<String, int> _apply(_V1Data v1, _Plan plan) {
    _raw.execute('ALTER TABLE sync_outbox RENAME TO sync_outbox_v1');
    _raw.execute(
      'CREATE TEMP TABLE nx_scope (entity_type TEXT NOT NULL, '
      'entity_id TEXT NOT NULL, PRIMARY KEY (entity_type, entity_id))',
    );
    for (final key in plan.createPatch.keys) {
      final split = key.indexOf(':');
      _raw.execute('INSERT INTO nx_scope (entity_type, entity_id) VALUES (?, ?)', [
        key.substring(0, split),
        key.substring(split + 1),
      ]);
    }
    _raw.execute(projectsV2Create);
    _raw.execute(tasksV2Create);
    _step('tables_created');
    _raw.execute(
      'INSERT INTO projects_v2 (id, owner_id, name, sort_order, version, '
      'sync_scope, deleted_at, created_at, updated_at) '
      'SELECT p.id, p.owner_id, p.name, p.sort_order, '
      "CASE WHEN s.entity_id IS NULL THEN p.version ELSE 0 END, "
      "CASE WHEN s.entity_id IS NULL THEN 'unclassified' ELSE 'synced' END, "
      'p.deleted_at, p.created_at, p.updated_at FROM projects p '
      "LEFT JOIN nx_scope s ON s.entity_type = 'project' AND s.entity_id = p.id",
    );
    _raw.execute(
      'INSERT INTO tasks_v2 (id, project_id, owner_id, parent_id, title, notes, '
      'status, priority, due_date, completed_at, sort_order, version, '
      'sync_scope, deleted_at, created_at, updated_at) '
      "SELECT t.id, t.project_id, t.owner_id, t.parent_id, t.title, COALESCE(t.notes, ''), "
      't.status, t.priority, t.due_date, t.completed_at, t.sort_order, '
      'CASE WHEN s.entity_id IS NULL THEN t.version ELSE 0 END, '
      "CASE WHEN s.entity_id IS NULL THEN 'unclassified' ELSE 'synced' END, "
      't.deleted_at, t.created_at, t.updated_at FROM tasks t '
      "LEFT JOIN nx_scope s ON s.entity_type = 'task' AND s.entity_id = t.id",
    );
    _step('domain_copied');
    _raw.execute('DROP TABLE tasks');
    _raw.execute('DROP TABLE projects');
    _raw.execute('ALTER TABLE projects_v2 RENAME TO projects');
    _raw.execute('ALTER TABLE tasks_v2 RENAME TO tasks');
    _raw.execute(tasksIndexCreate);
    _step('tables_swapped');
    for (final statement in schemaV2Statements) {
      if (statement.contains('CREATE TRIGGER')) {
        continue; // triggers come after the data is loaded
      }
      _raw.execute(statement);
    }
    _archiveV1(v1, plan);
    final seqs = _insertCreates(v1, plan);
    _step('outbox_migrated');
    for (final statement in schemaV2Statements) {
      if (statement.contains('CREATE TRIGGER')) {
        _raw.execute(statement);
      }
    }
    _raw.execute('INSERT INTO sync_state (singleton) VALUES (1)');
    final user = _boundUser();
    if (user != null) {
      _raw.execute(
        'INSERT INTO meta (key, value) VALUES (?, ?) '
        'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
        ['user_id', user],
      );
    }
    final archived =
        _raw.select('SELECT COUNT(*) AS n FROM sync_outbox_archive').single['n']
            as int;
    if (archived != v1.ops.length) {
      _abort('row_count_mismatch');
    }
    final projectCount =
        _raw.select('SELECT COUNT(*) AS n FROM projects').single['n'] as int;
    final taskCount =
        _raw.select('SELECT COUNT(*) AS n FROM tasks').single['n'] as int;
    if (projectCount != v1.projects.length || taskCount != v1.tasks.length) {
      _abort('row_count_mismatch');
    }
    _raw.execute('DROP TABLE sync_outbox_v1');
    _raw.execute('DROP TABLE nx_scope');
    if (_raw.select('PRAGMA foreign_key_check').isNotEmpty) {
      _abort('foreign_key_violation');
    }
    return {
      'projects': projectCount,
      'tasks': taskCount,
      'v1_operations': v1.ops.length,
      'class_s_entities': plan.createPatch.length,
      'class_u_entities':
          projectCount + taskCount - plan.createPatch.length,
      'live_creates': seqs,
      'archived_operations': archived,
    };
  }

  void _archiveV1(_V1Data v1, _Plan plan) {
    final at = _now().toIso8601String();
    for (final op in v1.ops) {
      _raw.execute(
        'INSERT INTO sync_outbox_archive (source, archive_reason, original_rowid, '
        'operation_id, entity_type, entity_id, operation_type, base_version, '
        'payload_json, created_at_utc, state, attempts, last_error, archived_at_utc) '
        "VALUES ('v1', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [
          plan.reason[op.rowid],
          op.rowid,
          op.operationId,
          op.entityType,
          op.entityId,
          op.operationType,
          op.baseVersion,
          op.payloadJson,
          op.createdAt,
          op.state,
          op.attempts,
          op.lastError,
          at,
        ],
      );
    }
  }

  /// Inserts the live create of every class S entity in v1 `rowid` order and
  /// links child creates to their parent's create. Returns the number inserted.
  int _insertCreates(_V1Data v1, _Plan plan) {
    final keys = plan.createOp.keys.toList()
      ..sort(
        (a, b) => plan.createOp[a]!.rowid.compareTo(plan.createOp[b]!.rowid),
      );
    final seqOf = <String, int>{};
    for (final key in keys) {
      final op = plan.createOp[key]!;
      final payload = jsonEncode(plan.createPatch[key]);
      _raw.execute(
        'INSERT INTO sync_outbox (operation_id, entity_type, entity_id, op_type, '
        'observed_base_version, base_version, payload_json, payload_bytes, '
        "created_at_utc, state, attempts) VALUES (?, ?, ?, 'create', 0, NULL, ?, ?, ?, 'pending', 0)",
        [
          op.operationId,
          op.entityType,
          op.entityId,
          payload,
          utf8.encode(payload).length,
          op.createdAt,
        ],
      );
      seqOf[key] = _raw.lastInsertRowId;
    }
    for (final key in keys) {
      if (!key.startsWith('task:')) {
        continue;
      }
      final task = v1.tasks[key.substring(5)]!;
      final parentId = task['parent_id'] as String?;
      final dependency = parentId != null
          ? seqOf['task:$parentId']
          : seqOf['project:${task['project_id']}'];
      if (dependency != null) {
        _raw.execute('UPDATE sync_outbox SET depends_on_seq = ? WHERE seq = ?', [
          dependency,
          seqOf[key],
        ]);
      }
    }
    return keys.length;
  }

  void _writeReport(MigrationReport report) {
    _raw.execute(
      'INSERT INTO sync_migration_report (migrated_at_utc, from_version, '
      'to_version, backup_file, digest_before, counts_json, warnings_json) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        _now().toIso8601String(),
        report.fromVersion,
        report.toVersion,
        report.backupFile,
        report.digestBefore,
        jsonEncode(report.counts),
        jsonEncode(report.warnings),
      ],
    );
  }

  /// After `COMMIT` the v2 schema is durable. A failing invariant here pauses
  /// synchronization and surfaces an error; it never rolls the migration back.
  void _postCommit() {
    final integrity = _raw.select('PRAGMA integrity_check');
    final fk = _raw.select('PRAGMA foreign_key_check');
    final ok =
        integrity.isNotEmpty && integrity.first.values.first == 'ok' && fk.isEmpty;
    if (!ok) {
      _raw.execute("UPDATE sync_state SET state = 'paused' WHERE singleton = 1");
      throw const RepositoryException(
        'post-commit invariant failed: synchronization paused; restore from the verified backup',
      );
    }
  }
}

final class _V1Op {
  const _V1Op({
    required this.rowid,
    required this.operationId,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.baseVersion,
    required this.payloadJson,
    required this.createdAt,
    required this.state,
    required this.attempts,
    required this.lastError,
  });

  final int rowid;
  final String operationId;
  final String entityType;
  final String entityId;
  final String operationType;
  final int baseVersion;
  final String payloadJson;
  final String createdAt;
  final String state;
  final int attempts;
  final String? lastError;
}

final class _V1Data {
  const _V1Data(this.ops, this.projects, this.tasks);

  final List<_V1Op> ops;
  final Map<String, Map<String, Object?>> projects;
  final Map<String, Map<String, Object?>> tasks;
}

final class _Plan {
  /// Class S entities (key `type:id`) and the create patch each one sends.
  final Map<String, Map<String, Object?>> createPatch = {};

  /// The v1 operation that becomes the live create of a class S entity.
  final Map<String, _V1Op> createOp = {};

  /// Archive reason per v1 `rowid`.
  final Map<int, String> reason = {};
  final List<String> warnings = [];
}
