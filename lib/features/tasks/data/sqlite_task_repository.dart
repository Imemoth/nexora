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

import 'entity_patch.dart';
import 'local_database.dart';
import 'outbox_store.dart';

/// Durable [TaskRepository] over a [LocalDatabase].
///
/// Every write runs in one `BEGIN IMMEDIATE` transaction. The domain row and its
/// `sync_outbox` operation commit together, and a failed write rolls back both.
/// The returned future completes only after `COMMIT`, so a successful save means
/// the change is durable.
///
/// Phase 3 S5 (schema v2): new entities store version 0 (never synchronized);
/// an edit queues a changed-fields-only patch that folds into a pending
/// operation; demo data and everything created under it is `local_only`;
/// unclassified entities (migrated legacy rows) never produce operations; a
/// task with live children cannot be deleted until the S3 atomicity protocol.
final class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository(
    this._db, {
    required this.ownerId,
    DateTime Function()? now,
    IdGenerator? ids,
  }) : _now = now ?? (() => DateTime.now().toUtc()),
       _ids = ids ?? RandomIdGenerator() {
    _outbox = OutboxStore(_db, ids: _ids, now: _now);
  }

  final LocalDatabase _db;
  late final OutboxStore _outbox;

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

  /// Marks a task deleted. The row is kept and, for a synchronized task, a delete
  /// operation is queued. The server-owned version is not changed by a local edit.
  /// Deleting an unknown or already deleted task is an error. A task with live
  /// children is refused (tree deletion needs the S3 atomicity protocol, so the
  /// server never sees a half-deleted tree).
  Future<void> softDeleteTask(String id) async {
    _run(
      () => _transaction(() {
        final row = _taskRow(id);
        if (row == null || row['deleted_at'] != null) {
          throw RepositoryException('no live task $id to delete');
        }
        final children = _db.raw.select(
          'SELECT 1 FROM tasks WHERE parent_id = ? AND deleted_at IS NULL LIMIT 1',
          [id],
        );
        if (children.isNotEmpty) {
          throw RepositoryException('task $id has live subtasks');
        }
        final now = _iso();
        _db.raw.execute(
          'UPDATE tasks SET deleted_at = ?, updated_at = ? WHERE id = ?',
          [now, now, id],
        );
        if (row['sync_scope'] == 'synced') {
          _outbox.recordDelete(
            entityType: 'task',
            entityId: id,
            storedVersion: row['version'] as int,
          );
        }
      }),
    );
  }

  /// Writes the demo projects and tasks in one transaction, only into an empty
  /// database that was never seeded. Seeded rows are `local_only`: they add no
  /// outbox entries and never synchronize, and neither does anything created
  /// under them later. Returns false, and changes nothing, otherwise.
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
            "sync_scope, created_at, updated_at) VALUES (?, ?, ?, ?, 0, 'local_only', ?, ?)",
            [project.id, ownerId, project.name, project.position, now, now],
          );
        }
        for (final task in tasks) {
          _insertTaskRow(task, now, 'local_only');
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
      final scope = _scopeForNewTask(task);
      _insertTaskRow(task, now, scope);
      if (scope == 'synced') {
        _outbox.recordCreate(
          entityType: 'task',
          entityId: task.id,
          patch: createPatchFromRow('task', _taskRow(task.id)!),
          parentType: task.parentId == null ? 'project' : 'task',
          parentId: task.parentId ?? task.projectId,
        );
      }
      return;
    }
    if (row['deleted_at'] != null) {
      throw RepositoryException('task ${task.id} was deleted');
    }
    if (_sameTask(row, task)) {
      return; // Repeated save of identical content writes nothing.
    }
    if (row['project_id'] != task.projectId) {
      throw RepositoryException('task ${task.id} cannot move to another project');
    }
    // completed_at is derived: set exactly while the task is done (local time,
    // kept once set), null for every other status including archived.
    final done = task.status == TaskStatus.done;
    final completedAt = done ? ((row['completed_at'] as String?) ?? now) : null;
    final changes = <String, Object?>{};
    if (row['parent_id'] != task.parentId) {
      changes['parent_id'] = task.parentId;
    }
    if (row['title'] != task.title) {
      changes['title'] = task.title;
    }
    if (((row['notes'] as String?) ?? '') != task.notes) {
      changes['notes'] = task.notes;
    }
    if (row['status'] != _statusColumn(task.status)) {
      changes['status'] = _statusColumn(task.status);
    }
    if (row['priority'] != _priorityColumn(task.priority)) {
      changes['priority'] = _priorityColumn(task.priority);
    }
    if (row['due_date'] != task.dueDate?.toIsoString()) {
      changes['due_date'] = task.dueDate?.toIsoString();
    }
    if (row['completed_at'] != completedAt) {
      changes['completed_at'] = completedAt;
    }
    if (row['sort_order'] != task.position) {
      changes['sort_order'] = task.position;
    }
    _db.raw.execute(
      'UPDATE tasks SET parent_id = ?, title = ?, notes = ?, '
      'status = ?, priority = ?, due_date = ?, completed_at = ?, sort_order = ?, '
      'updated_at = ? WHERE id = ?',
      [
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
    if (row['sync_scope'] == 'synced') {
      _outbox.recordEdit(
        entityType: 'task',
        entityId: task.id,
        patch: changes,
        storedVersion: row['version'] as int,
      );
    }
  }

  /// A new task is synchronized unless its project or parent is `local_only` or
  /// `unclassified`, in which case it inherits that scope (so descendants of demo
  /// data stay local, and nothing is ever sent for a parent the server lacks).
  String _scopeForNewTask(Task task) {
    final project = _db.raw.select(
      'SELECT sync_scope FROM projects WHERE id = ?',
      [task.projectId],
    );
    if (project.isEmpty) {
      throw RepositoryException('unknown project ${task.projectId}');
    }
    final projectScope = project.single['sync_scope'] as String;
    if (projectScope != 'synced') {
      return projectScope;
    }
    final parentId = task.parentId;
    if (parentId != null) {
      final parent = _taskRow(parentId);
      if (parent != null && parent['sync_scope'] != 'synced') {
        return parent['sync_scope'] as String;
      }
    }
    return 'synced';
  }

  void _insertTaskRow(Task task, String now, String scope) {
    _db.raw.execute(
      'INSERT INTO tasks (id, project_id, owner_id, parent_id, title, notes, '
      'status, priority, due_date, completed_at, sort_order, version, sync_scope, '
      'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)',
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
        scope,
        now,
        now,
      ],
    );
  }

  void _upsertProject(Project project) {
    final now = _iso();
    final existing = _db.raw.select(
      'SELECT version, sync_scope FROM projects WHERE id = ?',
      [project.id],
    );
    if (existing.isEmpty) {
      _db.raw.execute(
        'INSERT INTO projects (id, owner_id, name, sort_order, version, sync_scope, '
        "created_at, updated_at) VALUES (?, ?, ?, ?, 0, 'synced', ?, ?)",
        [project.id, ownerId, project.name, project.position, now, now],
      );
      _outbox.recordCreate(
        entityType: 'project',
        entityId: project.id,
        patch: {'name': project.name, 'sort_order': project.position},
      );
      return;
    }
    final current = _db.raw.select(
      'SELECT name, sort_order FROM projects WHERE id = ?',
      [project.id],
    ).single;
    final changes = <String, Object?>{};
    if (current['name'] != project.name) {
      changes['name'] = project.name;
    }
    if (current['sort_order'] != project.position) {
      changes['sort_order'] = project.position;
    }
    _db.raw.execute(
      'UPDATE projects SET name = ?, sort_order = ?, updated_at = ? '
      'WHERE id = ?',
      [project.name, project.position, now, project.id],
    );
    if (existing.single['sync_scope'] == 'synced') {
      _outbox.recordEdit(
        entityType: 'project',
        entityId: project.id,
        patch: changes,
        storedVersion: existing.single['version'] as int,
      );
    }
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
