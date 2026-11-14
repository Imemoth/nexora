/// SQL of local schema version 4 (Phase 4): one additive table for device-local
/// task reminders. It only creates a table and moves `user_version` in one
/// transaction, so it needs no backup and cannot touch existing data.
///
/// There is deliberately no foreign key to `tasks`: a pull from the server must
/// never delete a reminder as a side effect. The reminder service removes the
/// reminder of a task that no longer exists, and only after it has read the
/// task table.
library;

const List<String> schemaV4Statements = [
  '''
CREATE TABLE task_reminders (
  task_id TEXT NOT NULL PRIMARY KEY,
  remind_at_local TEXT NOT NULL CHECK (remind_at_local GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]'),
  state TEXT NOT NULL CHECK (state IN ('scheduled', 'notified', 'acknowledged')),
  snooze_until_utc INTEGER NULL,
  notified_at_utc INTEGER NULL,
  missed INTEGER NOT NULL DEFAULT 0 CHECK (missed IN (0, 1)),
  updated_at_utc INTEGER NOT NULL
)
''',
];
