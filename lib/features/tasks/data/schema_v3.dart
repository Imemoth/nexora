/// SQL of local schema version 3 (Phase 3 S6): one additive table. Migration 3 needs no backup because it only
/// creates a table and moves `user_version` in one transaction; migration 2 (the restructuring one) keeps its
/// verified backup.
library;

const List<String> schemaV3Statements = [
  // A pulled row whose project or parent task has not arrived yet waits here (inside the same transaction that
  // advances the cursor, so nothing is lost) and is applied as soon as its parent exists locally.
  '''
CREATE TABLE sync_pull_stage (
  entity_type TEXT NOT NULL CHECK (entity_type IN ('project', 'task')),
  entity_id TEXT NOT NULL,
  row_json TEXT NOT NULL,
  server_seq INTEGER NOT NULL,
  staged_at_utc TEXT NOT NULL,
  PRIMARY KEY (entity_type, entity_id)
)
''',
];
