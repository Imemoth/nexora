/// SQL of local schema version 6: the optional time of day of a due date moves
/// into `tasks.due_time` so it can synchronize like every other task field
/// (ADR 0004). Version 5 kept it in a local-only side table; that table was never
/// part of a release, but a version 5 file made by a development build holds real
/// times, so they are copied, not dropped.
///
/// * `due_time` is `HH:MM` (24 hour, no seconds, no zone) or NULL. NULL is the
///   genuine date-only state; nothing writes a default time.
/// * A time needs a date (check), exactly like the hosted constraint.
/// * Existing rows keep NULL, except those that had a version 5 time **and** a
///   date. A stray time without a date is discarded.
/// * Additive: no column is changed or removed from `tasks`. A build older than
///   version 6 refuses the file untouched.
library;

const List<String> schemaV6Statements = [
  '''
ALTER TABLE tasks ADD COLUMN due_time TEXT NULL CHECK (
  due_time IS NULL OR (
    due_date IS NOT NULL AND (due_time GLOB '[01][0-9]:[0-5][0-9]' OR due_time GLOB '2[0-3]:[0-5][0-9]')
  )
)
''',
  '''
UPDATE tasks SET due_time = (SELECT d.due_time FROM task_due_times d WHERE d.task_id = tasks.id)
WHERE due_date IS NOT NULL AND EXISTS (SELECT 1 FROM task_due_times d WHERE d.task_id = tasks.id)
''',
  'DROP TABLE task_due_times',
];
