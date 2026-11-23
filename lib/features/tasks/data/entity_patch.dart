/// Field lists and patch builders shared by the repository, the migration and the
/// outbox store. A patch holds only keys the server accepts (wire contract,
/// section 5). `owner_id`, `version`, `deleted_at` and timestamps are never sent.
library;

/// Fields a task update may carry. `project_id` is immutable and is not listed.
const List<String> taskUpdatableFields = [
  'parent_id',
  'title',
  'notes',
  'status',
  'priority',
  'due_date',
  'due_time',
  'completed_at',
  'sort_order',
];

/// Fields a project update may carry.
const List<String> projectUpdatableFields = ['name', 'sort_order'];

/// The patch of a create operation for [row] (a `projects` or `tasks` row): every
/// required field, and the optional ones only when set.
Map<String, Object?> createPatchFromRow(
  String entityType,
  Map<String, Object?> row,
) {
  if (entityType == 'project') {
    return {'name': row['name'], 'sort_order': row['sort_order']};
  }
  final patch = <String, Object?>{
    'project_id': row['project_id'],
    'title': row['title'],
    'notes': row['notes'] ?? '',
    'status': row['status'],
    'priority': row['priority'],
    'sort_order': row['sort_order'],
  };
  if (row['parent_id'] != null) {
    patch['parent_id'] = row['parent_id'];
  }
  if (row['due_date'] != null) {
    patch['due_date'] = row['due_date'];
  }
  // A time is sent only with its date (it cannot exist without one) and only
  // when there is one: a date-only task never sends a time.
  if (row['due_date'] != null && row['due_time'] != null) {
    patch['due_time'] = row['due_time'];
  }
  if (row['completed_at'] != null) {
    patch['completed_at'] = row['completed_at'];
  }
  return patch;
}

/// The fields of [local] whose value differs from [server] (a server row), as a
/// changed-fields-only update patch. `notes` compares `null` as `''`.
Map<String, Object?> changedFields(
  String entityType,
  Map<String, Object?> local,
  Map<String, Object?> server,
) {
  final fields = entityType == 'project'
      ? projectUpdatableFields
      : taskUpdatableFields;
  final changes = <String, Object?>{};
  for (final field in fields) {
    Object? mine = local[field];
    Object? theirs = server[field];
    if (field == 'notes') {
      mine = mine ?? '';
      theirs = theirs ?? '';
    }
    if (field == 'due_time') {
      // The server answers `17:30:00`; the wire and the local value are `17:30`.
      mine = normalizeDueTime(mine);
      theirs = normalizeDueTime(theirs);
    }
    if (mine != theirs) {
      changes[field] = mine;
    }
  }
  return pairDueTime(entityType, local, changes);
}

/// `HH:MM` for a time given as `HH:MM` or `HH:MM:SS` (what PostgreSQL returns),
/// null for anything else.
String? normalizeDueTime(Object? value) {
  if (value is! String) {
    return null;
  }
  final match = RegExp(r'^(\d{2}:\d{2})(?::00(?:\.0+)?)?$').firstMatch(value);
  return match?.group(1);
}

/// The date and the time of a task travel together: when a patch changes the
/// date and the task has a time, the time is sent too (even when unchanged), so
/// the server knows it is to be kept. Without it the server clears the time, which
/// is what it does for an older client that has never heard of times.
Map<String, Object?> pairDueTime(
  String entityType,
  Map<String, Object?> local,
  Map<String, Object?> changes,
) {
  if (entityType != 'task' ||
      !changes.containsKey('due_date') ||
      changes.containsKey('due_time') ||
      local['due_time'] == null ||
      local['due_date'] == null) {
    return changes;
  }
  return {...changes, 'due_time': local['due_time']};
}

/// Conflict kinds the local mirror accepts (the server's `sync_conflicts.kind`).
const Set<String> conflictKinds = {
  'field',
  'edit_deleted',
  'delete_edited',
  'parent_deleted',
  'parent_has_live_children',
  'cycle',
  'exists',
};
