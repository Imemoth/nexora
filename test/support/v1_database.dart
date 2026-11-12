import 'dart:convert';

import 'package:nexora/features/tasks/data/migrations.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builders for synthetic schema-1 databases. Every value is invented. A test
/// never opens a real user database: it writes one of these into a temporary
/// directory and migrates that copy.
const String v1Time = '2026-01-01T00:00:00.000Z';

/// Creates a schema-1 file at [path] and runs [statements] (inserts) on it.
void createV1File(String path, [List<String> statements = const []]) {
  final raw = sqlite3.open(path);
  try {
    for (final statement in migrationStatements.single) {
      raw.execute(statement);
    }
    for (final statement in statements) {
      raw.execute(statement);
    }
    raw.userVersion = 1;
  } finally {
    raw.close();
  }
}

String _q(String? value) =>
    value == null ? 'NULL' : "'${value.replaceAll("'", "''")}'";

String v1Project(
  String id, {
  String owner = 'owner-1',
  String name = 'Project',
  int version = 1,
  String? deletedAt,
}) {
  return 'INSERT INTO projects (id, owner_id, name, sort_order, version, deleted_at, '
      "created_at, updated_at) VALUES (${_q(id)}, ${_q(owner)}, ${_q(name)}, 0, $version, ${_q(deletedAt)}, '$v1Time', '$v1Time')";
}

String v1Task(
  String id,
  String projectId, {
  String owner = 'owner-1',
  String? parentId,
  String title = 'Task',
  String? notes,
  String status = 'open',
  int version = 1,
}) {
  return 'INSERT INTO tasks (id, project_id, owner_id, parent_id, title, notes, status, '
      'priority, due_date, completed_at, sort_order, version, deleted_at, created_at, updated_at) '
      "VALUES (${_q(id)}, ${_q(projectId)}, ${_q(owner)}, ${_q(parentId)}, ${_q(title)}, ${_q(notes)}, ${_q(status)}, "
      "'none', NULL, NULL, 0, $version, NULL, '$v1Time', '$v1Time')";
}

/// The v1 payload of a project operation (a full row, as Phase 2A wrote it).
Map<String, Object?> v1ProjectPayload(String id, {String name = 'Project'}) {
  return {'id': id, 'name': name, 'sort_order': 0};
}

Map<String, Object?> v1TaskPayload(
  String id,
  String projectId, {
  String? parentId,
  String title = 'Task',
  String notes = '',
  String status = 'open',
}) {
  return {
    'id': id,
    'project_id': projectId,
    'parent_id': parentId,
    'title': title,
    'notes': notes,
    'status': status,
    'priority': 'none',
    'due_date': null,
    'sort_order': 0,
  };
}

String v1Op(
  String operationId,
  String entityType,
  String entityId,
  Map<String, Object?> payload, {
  String operationType = 'upsert',
  int base = 0,
  String state = 'pending',
  int attempts = 0,
  String? lastError,
  String createdAt = v1Time,
}) {
  return 'INSERT INTO sync_outbox (operation_id, entity_type, entity_id, operation_type, '
      'base_version, payload_json, created_at_utc, state, attempts, last_error) VALUES '
      "(${_q(operationId)}, ${_q(entityType)}, ${_q(entityId)}, ${_q(operationType)}, $base, "
      "${_q(jsonEncode(payload))}, ${_q(createdAt)}, ${_q(state)}, $attempts, ${_q(lastError)})";
}

/// A small, fully class-S workspace: project p1, task t1 under it, subtask t2.
List<String> cleanV1Workspace() {
  return [
    "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
    v1Project('p1', name: 'Home'),
    v1Task('t1', 'p1', title: 'Parent'),
    v1Task('t2', 'p1', parentId: 't1', title: 'Child'),
    v1Op('op-p1', 'project', 'p1', v1ProjectPayload('p1', name: 'Home')),
    v1Op('op-t1', 'task', 't1', v1TaskPayload('t1', 'p1', title: 'Parent')),
    v1Op(
      'op-t2',
      'task',
      't2',
      v1TaskPayload('t2', 'p1', parentId: 't1', title: 'Child'),
    ),
  ];
}
