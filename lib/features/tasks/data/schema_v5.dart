/// SQL of local schema version 5: one additive table for the optional time of
/// day of a due date. Like version 4 it only creates a table and moves
/// `user_version` in one transaction, so it needs no backup and cannot touch
/// existing data.
///
/// The time lives beside `tasks`, not in it, on purpose: the `tasks` columns
/// mirror the hosted `tasks` table (whose `due_date` is a `date`), and the
/// outbox, pull and conflict code treat that mirror as a contract. A date-only
/// task has no row here, which is how "date only, no time" stays a genuine
/// state instead of becoming midnight. There is no foreign key to `tasks`, so
/// a pull can never delete or rewrite a time as a side effect.
///
/// The time is device-local until the hosted schema can store it (ADR 0004).
/// A build older than version 5 refuses a version 5 file untouched, so an older
/// client can never ignore a time and then change the date under it.
library;

const List<String> schemaV5Statements = [
  '''
CREATE TABLE task_due_times (
  task_id TEXT NOT NULL PRIMARY KEY,
  due_time TEXT NOT NULL CHECK (due_time GLOB '[0-2][0-9]:[0-5][0-9]')
)
''',
];
