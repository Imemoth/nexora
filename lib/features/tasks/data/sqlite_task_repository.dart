import 'dart:convert';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/task_repository.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/domain/task_validation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_database.dart';

/// Durable [TaskRepository] over a [LocalDatabase].
///
/// Every write runs in one `BEGIN IMMEDIATE` transaction. The domain row and its
/// `sync_outbox` operation commit together, and a failed write rolls back both.
/// The returned future completes only after `COMMIT`, so a successful save means
/// the change is durable.
final class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository(
    this._db, {
    required this.ownerId,
    DateTime Function()? now,
    IdGenerator? ids,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _ids = ids ?? RandomIdGenerator();

  final LocalDatabase _db;

  /// The owning user. Written to every local row.
  final String ownerId;
  final DateTime Function() _now;
  final IdGenerator _ids;

  // ---------------------------------------------------------------- reads

  @override
  Future<List<Project>> loadProjects() async {
    return _run(() {
      final rows = _db.raw.select(
        'SELECT id, name, sort_order FROM projects '
        'WHERE deleted_at IS NULL ORDER BY sort_order, id',
      );
      return [
        for (final row in rows)
          Project(
            id: row['id'] as String,
            name: row['name'] as String,
            position: (row['sort_order'] as int),
          ),
      ];
    });
  }

  @override
  Future<List<Task>> loadTasks() async {
    return _run(() {
      final rows = _db.raw.select(
        'SELECT id, project_id, parent_id, title, notes, status, priority, '
        'due_date, sort_order FROM tasks WHERE deleted_at IS NULL '
        'ORDER BY project_id, parent_id, sort_order, id',
      );
      return [
        for (final row in rows)
          Task(
            id: row['id'] as String,
            projectId: row['project_id'] as String,
            parentId: row['parent_id'] as String?,
            title: row['title'] as String,
            notes: (row['notes'] as String?) ?? '',
            status: _statusFromColumn(row['status'] as String),
            priority: _priorityFromColumn(row['priority'] as String),
            dueDate: _dateFromColumn(row['due_date'] as String?),
            position: row['sort_order'] as int,
          ),
      ];
    });
  }

  // --------------------------------------------------------------- writes

  @override
  Future<void> saveTask(Task task) async {
    if (task.title.length > maxTitleLength) {
      // The server accepts at most 200 UTF-16 units. Refuse here so the local
      // database never holds a title that could not be pushed later.
      throw RepositoryException('title exceeds $maxTitleLength characters');
    }
    _run(() => _transaction(() => _upsertTask(task)));
  }

  /// Inserts or updates a project, in one transaction with its outbox entry.
  Future<void> saveProject(Project project) async {
    _run(() => _transaction(() => _upsertProject(project)));
  }

  /// Marks a task deleted. The row is kept and a delete operation is queued. The
  /// server-owned version is not changed by a local edit. Deleting an unknown or
  /// already deleted task is an error.
  Future<void> softDeleteTask(String id) async {
    _run(
      () => _transaction(() {
        final row = _taskRow(id);
        if (row == null || row['deleted_at'] != null) {
          throw RepositoryException('no live task $id to delete');
        }
        final version = row['version'] as int;
        final now = _iso();
        _db.raw.execute(
          'UPDATE tasks SET deleted_at = ?, updated_at = ? WHERE id = ?',
          [now, now, id],
        );
        _enqueue(
          entityType: 'task',
          entityId: id,
          operationType: 'delete',
          baseVersion: _baseVersionFor('task', id, version),
          payload: {'id': id, 'deleted_at': now},
        );
      }),
    );
  }

  /// Writes the demo projects and tasks in one transaction, only into an empty
  /// database that was never seeded. Seeded rows are local and add no outbox
  /// entries, so they never sync. Returns false, and changes nothing, otherwise.
  Future<bool> seedDemoData({
    required List<Project> projects,
    required List<Task> tasks,
  }) async {
    return _run(
      () => _transaction(() {
        if (_metaValue('demo_seeded') != null || _hasLiveRows()) {
          return false;
        }
        final now = _iso();
        for (final project in projects) {
          _db.raw.execute(
            'INSERT INTO projects (id, owner_id, name, sort_order, version, '
            'created_at, updated_at) VALUES (?, ?, ?, ?, 1, ?, ?)',
            [project.id, ownerId, project.name, project.position, now, now],
          );
        }
        for (final task in tasks) {
          _insertTaskRow(task, now);
        }
        _setMeta('demo_seeded', now);
        return true;
      }),
    );
  }

  /// Creates the default project when the workspace has none and has never had
  /// one. Returns the new project, or null when nothing was created.
  Future<Project?> ensureDefaultProject(String name) async {
    return _run(
      () => _transaction(() {
        if (_metaValue('default_project_created') != null ||
            _hasLiveProjects()) {
          return null;
        }
        final project = Project(id: _ids.nextId(), name: name, position: 0);
        _upsertProject(project);
        _setMeta('default_project_created', _iso());
        return project;
      }),
    );
  }

  // ------------------------------------------------------ internal writes

  void _upsertTask(Task task) {
    final row = _taskRow(task.id);
    final now = _iso();
    if (row == null) {
      _insertTaskRow(task, now);
      _enqueue(
        entityType: 'task',
        entityId: task.id,
        operationType: 'upsert',
        baseVersion: 0,
        payload: _taskPayload(task),
      );
      return;
    }
    if (row['deleted_at'] != null) {
      throw RepositoryException('task ${task.id} was deleted');
    }
    if (_sameTask(row, task)) {
      return; // Repeated save of identical content writes nothing.
    }
    final version = row['version'] as int;
    final becameDone =
        task.status == TaskStatus.done &&
        row['status'] != _statusColumn(TaskStatus.done);
    final completedAt = task.status == TaskStatus.done
        ? (becameDone ? now : row['completed_at'] as String?)
        : null;
    _db.raw.execute(
      'UPDATE tasks SET project_id = ?, parent_id = ?, title = ?, notes = ?, '
      'status = ?, priority = ?, due_date = ?, completed_at = ?, sort_order = ?, '
      'updated_at = ? WHERE id = ?',
      [
        task.projectId,
        task.parentId,
        task.title,
        task.notes,
        _statusColumn(task.status),
        _priorityColumn(task.priority),
        task.dueDate?.toIsoString(),
        completedAt,
        task.position,
        now,
        task.id,
      ],
    );
    _enqueue(
      entityType: 'task',
      entityId: task.id,
      operationType: 'upsert',
      baseVersion: _baseVersionFor('task', task.id, version),
      payload: _taskPayload(task),
    );
  }

  void _insertTaskRow(Task task, String now) {
    _db.raw.execute(
      'INSERT INTO tasks (id, project_id, owner_id, parent_id, title, notes, '
      'status, priority, due_date, completed_at, sort_order, version, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
      [
        task.id,
        task.projectId,
        ownerId,
        task.parentId,
        task.title,
        task.notes,
        _statusColumn(task.status),
        _priorityColumn(task.priority),
        task.dueDate?.toIsoString(),
        task.status == TaskStatus.done ? now : null,
        task.position,
        now,
        now,
      ],
    );
  }

  void _upsertProject(Project project) {
    final now = _iso();
    final existing = _db.raw.select(
      'SELECT version FROM projects WHERE id = ?',
      [project.id],
    );
    if (existing.isEmpty) {
      _db.raw.execute(
        'INSERT INTO projects (id, owner_id, name, sort_order, version, created_at, '
        'updated_at) VALUES (?, ?, ?, ?, 1, ?, ?)',
        [project.id, ownerId, project.name, project.position, now, now],
      );
      _enqueue(
        entityType: 'project',
        entityId: project.id,
        operationType: 'upsert',
        baseVersion: 0,
        payload: {
          'id': project.id,
          'name': project.name,
          'sort_order': project.position,
        },
      );
      return;
    }
    final version = existing.single['version'] as int;
    _db.raw.execute(
      'UPDATE projects SET name = ?, sort_order = ?, updated_at = ? '
      'WHERE id = ?',
      [project.name, project.position, now, project.id],
    );
    _enqueue(
      entityType: 'project',
      entityId: project.id,
      operationType: 'upsert',
      baseVersion: _baseVersionFor('project', project.id, version),
      payload: {
        'id': project.id,
        'name': project.name,
        'sort_order': project.position,
      },
    );
  }

  /// The `base_version` for a new operation on an entity (decision D-V).
  ///
  /// Local edits never change the stored version. Once a create is queued but not
  /// yet acknowledged by the server, the entity has no server version, so its
  /// operations carry 0. Otherwise the stored last-known server version is used.
  int _baseVersionFor(String entityType, String entityId, int storedVersion) {
    final pending = _db.raw.select(
      "SELECT 1 FROM sync_outbox WHERE entity_type = ? AND entity_id = ? "
      "AND base_version = 0 AND state IN ('pending', 'sent') LIMIT 1",
      [entityType, entityId],
    );
    return pending.isEmpty ? storedVersion : 0;
  }

  void _enqueue({
    required String entityType,
    required String entityId,
    required String operationType,
    required int baseVersion,
    required Map<String, Object?> payload,
  }) {
    _db.raw.execute(
      'INSERT INTO sync_outbox (operation_id, entity_type, entity_id, '
      'operation_type, base_version, payload_json, created_at_utc, state, attempts) '
      "VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0)",
      [
        _ids.nextId(),
        entityType,
        entityId,
        operationType,
        baseVersion,
        jsonEncode(payload),
        _iso(),
      ],
    );
  }

  // ------------------------------------------------------------ helpers

  Map<String, Object?>? _taskRow(String id) {
    final rows = _db.raw.select('SELECT * FROM tasks WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return null;
    }
    return {for (final key in rows.single.keys) key: rows.single[key]};
  }

  bool _sameTask(Map<String, Object?> row, Task task) {
    return row['project_id'] == task.projectId &&
        row['parent_id'] == task.parentId &&
        row['title'] == task.title &&
        (row['notes'] ?? '') == task.notes &&
        row['status'] == _statusColumn(task.status) &&
        row['priority'] == _priorityColumn(task.priority) &&
        row['due_date'] == task.dueDate?.toIsoString() &&
        row['sort_order'] == task.position;
  }

  Map<String, Object?> _taskPayload(Task task) => {
    'id': task.id,
    'project_id': task.projectId,
    'parent_id': task.parentId,
    'title': task.title,
    'notes': task.notes,
    'status': _statusColumn(task.status),
    'priority': _priorityColumn(task.priority),
    'due_date': task.dueDate?.toIsoString(),
    'sort_order': task.position,
  };

  bool _hasLiveRows() {
    final rows = _db.raw.select(
      'SELECT (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL) + '
      '(SELECT COUNT(*) FROM projects WHERE deleted_at IS NULL) AS n',
    );
    return (rows.single['n'] as int) > 0;
  }

  bool _hasLiveProjects() {
    final rows = _db.raw.select(
      'SELECT COUNT(*) AS n FROM projects WHERE deleted_at IS NULL',
    );
    return (rows.single['n'] as int) > 0;
  }

  String? _metaValue(String key) {
    final rows = _db.raw.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  void _setMeta(String key, String value) {
    _db.raw.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }

  String _iso() => _now().toUtc().toIso8601String();

  T _transaction<T>(T Function() body) {
    final raw = _db.raw;
    raw.execute('BEGIN IMMEDIATE;');
    try {
      final result = body();
      raw.execute('COMMIT;');
      return result;
    } catch (_) {
      if (!raw.autocommit) {
        raw.execute('ROLLBACK;');
      }
      rethrow;
    }
  }

  T _run<T>(T Function() body) {
    try {
      return body();
    } on SqliteException catch (error) {
      throw RepositoryException(error.message);
    }
  }
}

String _statusColumn(TaskStatus status) => switch (status) {
  TaskStatus.open => 'open',
  TaskStatus.inProgress => 'in_progress',
  TaskStatus.review => 'review',
  TaskStatus.done => 'done',
  TaskStatus.archived => 'archived',
};

String _priorityColumn(TaskPriority priority) => switch (priority) {
  TaskPriority.none => 'none',
  TaskPriority.low => 'low',
  TaskPriority.medium => 'medium',
  TaskPriority.high => 'high',
};

TaskStatus _statusFromColumn(String value) => switch (value) {
  'open' => TaskStatus.open,
  'in_progress' => TaskStatus.inProgress,
  'review' => TaskStatus.review,
  'done' => TaskStatus.done,
  'archived' => TaskStatus.archived,
  _ => throw RepositoryException('unknown stored status "$value"'),
};

TaskPriority _priorityFromColumn(String value) => switch (value) {
  'none' => TaskPriority.none,
  'low' => TaskPriority.low,
  'medium' => TaskPriority.medium,
  'high' => TaskPriority.high,
  _ => throw RepositoryException('unknown stored priority "$value"'),
};

CalendarDate? _dateFromColumn(String? value) {
  if (value == null) {
    return null;
  }
  final parts = value.split('-');
  return CalendarDate(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}
