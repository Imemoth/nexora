/// Versioned, forward-only schema migrations for the local SQLite file.
///
/// Each migration runs in its own transaction, together with the update of
/// `PRAGMA user_version`. A migration that fails rolls back and leaves the file at
/// its previous version. Never edit a migration that has shipped; add a new one.
///
/// Canonical vocabularies (shared with the Supabase session; see the Phase 2A
/// plan, section 2): task status `open, in_progress, review, done, archived`;
/// task priority `none, low, medium, high`. The live Supabase check constraint
/// does not yet accept `review`, `archived` or `none`. That correction is a
/// separate, approved Supabase change and is not part of this file.
const List<List<String>> migrationStatements = [
  // Version 1: the initial local schema.
  [
    '''
CREATE TABLE projects (
  id TEXT NOT NULL PRIMARY KEY,
  owner_id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 200),
  sort_order INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
    '''
CREATE TABLE tasks (
  id TEXT NOT NULL PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects (id),
  owner_id TEXT NOT NULL,
  parent_id TEXT NULL,
  title TEXT NOT NULL CHECK (length(trim(title)) BETWEEN 1 AND 500),
  notes TEXT NULL,
  status TEXT NOT NULL CHECK (status IN ('open', 'in_progress', 'review', 'done', 'archived')),
  priority TEXT NOT NULL CHECK (priority IN ('none', 'low', 'medium', 'high')),
  due_date TEXT NULL CHECK (due_date IS NULL OR due_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  completed_at TEXT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (id, project_id),
  FOREIGN KEY (parent_id, project_id) REFERENCES tasks (id, project_id)
)
''',
    'CREATE INDEX tasks_by_project ON tasks (project_id, parent_id, sort_order)',
    '''
CREATE TABLE meta (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
)
''',
    '''
CREATE TABLE sync_outbox (
  operation_id TEXT NOT NULL PRIMARY KEY,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('project', 'task')),
  entity_id TEXT NOT NULL,
  operation_type TEXT NOT NULL CHECK (operation_type IN ('upsert', 'delete')),
  base_version INTEGER NOT NULL CHECK (base_version >= 0),
  payload_json TEXT NOT NULL,
  created_at_utc TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'sent', 'acked', 'failed')),
  attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error TEXT NULL
)
''',
  ],
];
