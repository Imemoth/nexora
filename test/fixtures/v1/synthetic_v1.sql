-- Frozen copy of the shipped v1 schema (independent of lib/) followed by SYNTHETIC rows.
CREATE TABLE projects (
  id TEXT NOT NULL PRIMARY KEY,
  owner_id TEXT NOT NULL,
  name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 200),
  sort_order INTEGER NOT NULL DEFAULT 0,
  version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
  deleted_at TEXT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
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
);
CREATE INDEX tasks_by_project ON tasks (project_id, parent_id, sort_order);
CREATE TABLE meta (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
);
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
);

-- SYNTHETIC DATA: invented for tests, no real user content.
INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-synthetic-0001');
INSERT INTO projects (id, owner_id, name, sort_order, version, deleted_at, created_at, updated_at) VALUES
  ('p-synth-a', 'owner-synthetic-0001', 'Synthetic project A', 0, 3, NULL, '2026-01-01T08:00:00.000Z', '2026-01-02T08:00:00.000Z'),
  ('p-synth-b', 'owner-synthetic-0001', 'Synthetic project B', 1, 1, '2026-01-03T09:00:00.000Z', '2026-01-01T08:00:00.000Z', '2026-01-03T09:00:00.000Z');
INSERT INTO tasks (id, project_id, owner_id, parent_id, title, notes, status, priority, due_date, completed_at, sort_order, version, deleted_at, created_at, updated_at) VALUES
  ('t-synth-1', 'p-synth-a', 'owner-synthetic-0001', NULL, 'Synthetic parent', NULL, 'open', 'high', '2026-02-01', NULL, 0, 2, NULL, '2026-01-01T08:00:00.000Z', '2026-01-02T08:00:00.000Z'),
  ('t-synth-2', 'p-synth-a', 'owner-synthetic-0001', 't-synth-1', 'Synthetic child', '', 'done', 'none', NULL, '2026-01-02T10:00:00.000Z', 1, 1, NULL, '2026-01-01T08:00:00.000Z', '2026-01-02T10:00:00.000Z'),
  ('t-synth-3', 'p-synth-a', 'owner-synthetic-0001', NULL, 'Synthetic deleted', 'notes text', 'archived', 'low', NULL, NULL, 2, 1, '2026-01-04T00:00:00.000Z', '2026-01-01T08:00:00.000Z', '2026-01-04T00:00:00.000Z');
INSERT INTO sync_outbox (operation_id, entity_type, entity_id, operation_type, base_version, payload_json, created_at_utc, state, attempts, last_error) VALUES
  ('00000000-0000-4000-8000-000000000001', 'project', 'p-synth-a', 'upsert', 0, '{"id":"p-synth-a","name":"Synthetic project A"}', '2026-01-01T08:00:01.000Z', 'acked', 1, NULL),
  ('00000000-0000-4000-8000-000000000002', 'task', 't-synth-1', 'upsert', 0, '{"id":"t-synth-1","title":"Synthetic parent"}', '2026-01-01T08:00:02.000Z', 'sent', 2, NULL),
  ('00000000-0000-4000-8000-000000000003', 'task', 't-synth-1', 'upsert', 0, '{"id":"t-synth-1","title":"Synthetic parent","priority":"high"}', '2026-01-02T08:00:00.000Z', 'pending', 0, NULL),
  ('00000000-0000-4000-8000-000000000004', 'task', 't-synth-3', 'delete', 1, '{"id":"t-synth-3","deleted_at":"2026-01-04T00:00:00.000Z"}', '2026-01-04T00:00:00.000Z', 'failed', 3, 'synthetic failure'),
  ('00000000-0000-4000-8000-000000000005', 'task', 't-synth-2', 'upsert', 1, '{"id":"t-synth-2","status":"done"}', '2026-01-02T10:00:00.000Z', 'pending', 0, NULL);
