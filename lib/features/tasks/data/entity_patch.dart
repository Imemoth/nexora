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
    if (mine != theirs) {
      changes[field] = mine;
    }
  }
  return changes;
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
