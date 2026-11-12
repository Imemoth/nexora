/// SQL of local schema version 2 (Phase 3 S5). Forward-only: migration 1 stays
/// frozen in `migrations.dart`. These statements are used by the v1 to v2
/// migration (`migration_v2.dart`) and are the only place the v2 shape is defined.
///
/// Design: docs/coordination/phase-3-s5-outbox-v2.md. Key points:
/// - `sync_scope` has no default, so a writer that forgets it fails loudly
///   instead of silently making a row synchronizable.
/// - An operation's identity, and its payload and base once claimed, never
///   change (triggers). Results are written once. History is never deleted.
library;

/// Largest payload of one operation: 224 KiB.
const int maxPayloadBytes = 229376;

/// Rebuilt `projects` (created under a temporary name, then renamed).
const String projectsV2Create = '''
CREATE TABLE projects_v2 (
  id TEXT NOT NULL PRIMARY KEY,
  owner_id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 200),
  sort_order INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 0 CHECK (version >= 0),
  sync_scope TEXT NOT NULL CHECK (sync_scope IN ('synced', 'local_only', 'unclassified')),
  deleted_at TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''';

/// Rebuilt `tasks`. The foreign keys name the final table names.
const String tasksV2Create = '''
CREATE TABLE tasks_v2 (
  id TEXT NOT NULL PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects (id),
  owner_id TEXT NOT NULL,
  parent_id TEXT NULL,
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 200),
  notes TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL CHECK (status IN ('open', 'in_progress', 'review', 'done', 'archived')),
  priority TEXT NOT NULL CHECK (priority IN ('none', 'low', 'medium', 'high')),
  due_date TEXT NULL CHECK (due_date IS NULL OR due_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  completed_at TEXT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 0 CHECK (version >= 0),
  sync_scope TEXT NOT NULL CHECK (sync_scope IN ('synced', 'local_only', 'unclassified')),
  deleted_at TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (id, project_id),
  FOREIGN KEY (parent_id, project_id) REFERENCES tasks (id, project_id)
)
''';

const String tasksIndexCreate =
    'CREATE INDEX tasks_by_project ON tasks (project_id, parent_id, sort_order)';

/// New tables, indexes and triggers created by the migration, in order.
const List<String> schemaV2Statements = [
  '''
CREATE TABLE sync_outbox (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  operation_id TEXT NOT NULL UNIQUE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('project', 'task')),
  entity_id TEXT NOT NULL,
  op_type TEXT NOT NULL CHECK (op_type IN ('create', 'update', 'delete')),
  observed_base_version INTEGER NOT NULL CHECK (observed_base_version >= 0),
  base_version INTEGER NULL CHECK (base_version IS NULL OR base_version >= 0),
  payload_json TEXT NOT NULL,
  payload_bytes INTEGER NOT NULL CHECK (payload_bytes BETWEEN 1 AND 229376),
  created_at_utc TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'in_flight', 'applied', 'conflict', 'rejected')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error TEXT NULL,
  request_id TEXT NULL,
  sent_at TEXT NULL,
  server_result_json TEXT NULL,
  applied_version INTEGER NULL,
  version_before INTEGER NULL,
  error_code TEXT NULL,
  conflict_id TEXT NULL,
  handled_at_utc TEXT NULL,
  depends_on_seq INTEGER NULL REFERENCES sync_outbox (seq),
  CHECK (op_type <> 'create' OR (observed_base_version = 0 AND (base_version IS NULL OR base_version = 0))),
  CHECK (op_type = 'create' OR observed_base_version > 0 OR depends_on_seq IS NOT NULL),
  CHECK (op_type = 'create' OR base_version IS NULL OR base_version >= 1)
)
''',
  'CREATE INDEX sync_outbox_by_entity ON sync_outbox (entity_type, entity_id, seq)',
  'CREATE INDEX sync_outbox_by_state ON sync_outbox (state, seq)',
  '''
CREATE UNIQUE INDEX sync_one_inflight ON sync_outbox (entity_type, entity_id)
  WHERE state = 'in_flight'
''',
  '''
CREATE UNIQUE INDEX sync_one_live_create ON sync_outbox (entity_type, entity_id)
  WHERE op_type = 'create' AND state IN ('pending', 'in_flight', 'applied')
''',
  '''
CREATE TABLE sync_outbox_archive (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL CHECK (source IN ('v1', 'v2')),
  archive_reason TEXT NOT NULL,
  original_rowid INTEGER NULL,
  operation_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  base_version INTEGER NULL,
  payload_json TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  state TEXT NOT NULL,
  attempts INTEGER NOT NULL,
  last_error TEXT NULL,
  archived_at_utc TEXT NOT NULL
)
''',
  '''
CREATE TABLE sync_entity_snapshot (
  entity_type TEXT NOT NULL CHECK (entity_type IN ('project', 'task')),
  entity_id TEXT NOT NULL,
  row_json TEXT NOT NULL,
  server_version INTEGER NOT NULL CHECK (server_version >= 0),
  source TEXT NOT NULL CHECK (source IN ('ack', 'conflict', 'pull')),
  updated_at_utc TEXT NOT NULL,
  PRIMARY KEY (entity_type, entity_id)
)
''',
  '''
CREATE TABLE sync_conflicts_local (
  id TEXT NOT NULL PRIMARY KEY,
  operation_id TEXT NOT NULL UNIQUE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('project', 'task')),
  entity_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('field', 'edit_deleted', 'delete_edited', 'parent_deleted', 'parent_has_live_children', 'cycle', 'exists')),
  fields_json TEXT NOT NULL,
  base_version INTEGER NOT NULL,
  server_version INTEGER NULL,
  server_value_json TEXT NOT NULL,
  client_value_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved_server', 'resolved_local')),
  resolution_source TEXT NULL,
  created_at_utc TEXT NOT NULL,
  resolved_at_utc TEXT NULL,
  CHECK ((status = 'open') = (resolved_at_utc IS NULL)),
  CHECK (status = 'open' OR resolution_source IS NOT NULL)
)
''',
  '''
CREATE TABLE sync_state (
  singleton INTEGER NOT NULL PRIMARY KEY CHECK (singleton = 1),
  device_id TEXT NULL,
  cursor INTEGER NOT NULL DEFAULT 0 CHECK (cursor >= 0),
  state TEXT NOT NULL DEFAULT 'idle' CHECK (state IN ('idle', 'paused'))
)
''',
  '''
CREATE TABLE sync_migration_report (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  migrated_at_utc TEXT NOT NULL,
  from_version INTEGER NOT NULL,
  to_version INTEGER NOT NULL,
  backup_file TEXT NULL,
  digest_before TEXT NOT NULL,
  counts_json TEXT NOT NULL,
  warnings_json TEXT NOT NULL
)
''',
  // ---- triggers -------------------------------------------------------------
  '''
CREATE TRIGGER sync_outbox_identity_immutable
BEFORE UPDATE OF operation_id, entity_type, entity_id, op_type, observed_base_version, created_at_utc, seq
ON sync_outbox
WHEN NEW.operation_id IS NOT OLD.operation_id OR NEW.entity_type IS NOT OLD.entity_type
  OR NEW.entity_id IS NOT OLD.entity_id OR NEW.op_type IS NOT OLD.op_type
  OR NEW.observed_base_version IS NOT OLD.observed_base_version
  OR NEW.created_at_utc IS NOT OLD.created_at_utc OR NEW.seq IS NOT OLD.seq
BEGIN SELECT RAISE(ABORT, 'outbox operation identity is immutable'); END
''',
  '''
CREATE TRIGGER sync_outbox_claimed_immutable
BEFORE UPDATE OF payload_json, payload_bytes, base_version ON sync_outbox
WHEN OLD.base_version IS NOT NULL
  AND (NEW.payload_json IS NOT OLD.payload_json OR NEW.payload_bytes IS NOT OLD.payload_bytes
       OR NEW.base_version IS NOT OLD.base_version)
BEGIN SELECT RAISE(ABORT, 'a claimed outbox operation is immutable'); END
''',
  '''
CREATE TRIGGER sync_outbox_state_machine
BEFORE UPDATE OF state ON sync_outbox
WHEN NEW.state IS NOT OLD.state AND NOT (
  (OLD.state = 'pending' AND NEW.state = 'in_flight')
  OR (OLD.state = 'in_flight' AND NEW.state IN ('pending', 'applied', 'conflict', 'rejected')))
BEGIN SELECT RAISE(ABORT, 'illegal outbox state transition'); END
''',
  '''
CREATE TRIGGER sync_outbox_result_write_once
BEFORE UPDATE OF server_result_json, applied_version, version_before, error_code, conflict_id ON sync_outbox
WHEN OLD.state IN ('applied', 'conflict', 'rejected')
  AND (NEW.server_result_json IS NOT OLD.server_result_json OR NEW.applied_version IS NOT OLD.applied_version
       OR NEW.version_before IS NOT OLD.version_before OR NEW.error_code IS NOT OLD.error_code
       OR NEW.conflict_id IS NOT OLD.conflict_id)
BEGIN SELECT RAISE(ABORT, 'an outbox result is written once'); END
''',
  '''
CREATE TRIGGER sync_outbox_handled_write_once
BEFORE UPDATE OF handled_at_utc ON sync_outbox
WHEN NEW.handled_at_utc IS NOT OLD.handled_at_utc
  AND (OLD.handled_at_utc IS NOT NULL OR OLD.state NOT IN ('conflict', 'rejected'))
BEGIN SELECT RAISE(ABORT, 'handled marker is written once, for conflict or rejected operations only'); END
''',
  '''
CREATE TRIGGER sync_outbox_no_delete_claimed
BEFORE DELETE ON sync_outbox
WHEN OLD.state <> 'pending' OR OLD.base_version IS NOT NULL
BEGIN SELECT RAISE(ABORT, 'claimed outbox operations are never deleted'); END
''',
  '''
CREATE TRIGGER sync_outbox_archive_no_update
BEFORE UPDATE ON sync_outbox_archive
BEGIN SELECT RAISE(ABORT, 'the outbox archive is append-only'); END
''',
  '''
CREATE TRIGGER sync_outbox_archive_no_delete
BEFORE DELETE ON sync_outbox_archive
BEGIN SELECT RAISE(ABORT, 'the outbox archive is append-only'); END
''',
  '''
CREATE TRIGGER sync_conflicts_evidence_immutable
BEFORE UPDATE OF id, operation_id, entity_type, entity_id, kind, fields_json, base_version, server_version,
  server_value_json, client_value_json, created_at_utc ON sync_conflicts_local
BEGIN SELECT RAISE(ABORT, 'conflict evidence is immutable'); END
''',
  '''
CREATE TRIGGER sync_conflicts_resolution_write_once
BEFORE UPDATE OF status, resolution_source, resolved_at_utc ON sync_conflicts_local
WHEN OLD.status <> 'open'
BEGIN SELECT RAISE(ABORT, 'a conflict resolution is written once'); END
''',
  '''
CREATE TRIGGER sync_conflicts_no_delete
BEFORE DELETE ON sync_conflicts_local
BEGIN SELECT RAISE(ABORT, 'conflict records are never deleted'); END
''',
  '''
CREATE TRIGGER tasks_project_immutable
BEFORE UPDATE OF project_id ON tasks
WHEN NEW.project_id <> OLD.project_id
BEGIN SELECT RAISE(ABORT, 'a task cannot move to another project'); END
''',
];
