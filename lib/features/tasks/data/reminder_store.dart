import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_database.dart';

/// SQLite persistence of device-local reminders (table `task_reminders`).
///
/// Every state change is a single guarded UPDATE, so two ticks (or a tick and a
/// user action) can never both win: [claim] succeeds for exactly one caller and
/// is committed before any notification is shown. That is what makes a restart
/// unable to show the same reminder twice.
final class ReminderStore implements ReminderPersistence {
  ReminderStore(this._db);

  final LocalDatabase _db;

  Database get _raw => _db.raw;

  T _run<T>(T Function() body) {
    try {
      return body();
    } on SqliteException catch (error) {
      throw RepositoryException('reminder storage failed: ${error.message}');
    }
  }

  static const _columns =
      'task_id, remind_at_local, state, snooze_until_utc, notified_at_utc, missed';

  Reminder? _fromRow(Row row) {
    final wall = LocalWallTime.tryParse(row['remind_at_local'] as String);
    final state = switch (row['state'] as String) {
      'scheduled' => ReminderState.scheduled,
      'notified' => ReminderState.notified,
      'acknowledged' => ReminderState.acknowledged,
      _ => null,
    };
    if (wall == null || state == null) {
      return null;
    }
    DateTime? utc(Object? ms) => ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);
    return Reminder(
      taskId: row['task_id'] as String,
      remindAt: wall,
      state: state,
      snoozeUntilUtc: utc(row['snooze_until_utc']),
      notifiedAtUtc: utc(row['notified_at_utc']),
      missed: (row['missed'] as int) == 1,
    );
  }

  @override
  Reminder? get(String taskId) => _run(() {
    final rows = _raw.select(
      'SELECT $_columns FROM task_reminders WHERE task_id = ?',
      [taskId],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  });

  @override
  List<Reminder> all() => _run(() {
    final rows = _raw.select(
      'SELECT $_columns FROM task_reminders ORDER BY remind_at_local, task_id',
    );
    return [for (final row in rows) ?_fromRow(row)];
  });

  /// Creates or replaces the reminder of [taskId] as a fresh scheduled one.
  @override
  void schedule(String taskId, LocalWallTime wall, DateTime nowUtc) => _run(() {
    _raw.execute(
      'INSERT INTO task_reminders (task_id, remind_at_local, state, '
      'snooze_until_utc, notified_at_utc, missed, updated_at_utc) '
      "VALUES (?, ?, 'scheduled', NULL, NULL, 0, ?) "
      'ON CONFLICT(task_id) DO UPDATE SET remind_at_local = excluded.remind_at_local, '
      "state = 'scheduled', snooze_until_utc = NULL, notified_at_utc = NULL, "
      'missed = 0, updated_at_utc = excluded.updated_at_utc',
      [taskId, wall.toIsoString(), nowUtc.millisecondsSinceEpoch],
    );
  });

  /// Removes the reminder. Returns whether one existed.
  @override
  bool cancel(String taskId) => _run(() {
    _raw.execute('DELETE FROM task_reminders WHERE task_id = ?', [taskId]);
    return _raw.updatedRows == 1;
  });

  /// Marks a due reminder as notified, only if it is still exactly the one the
  /// caller evaluated (same wall time, same snooze). Returns true for the one
  /// caller that won; that caller then shows the notification.
  @override
  bool claim(Reminder expected, DateTime nowUtc, {required bool missed}) =>
      _run(() {
        _raw.execute(
          "UPDATE task_reminders SET state = 'notified', notified_at_utc = ?, "
          "missed = ?, updated_at_utc = ? WHERE task_id = ? AND state = 'scheduled' "
          'AND remind_at_local = ? AND snooze_until_utc IS ?',
          [
            nowUtc.millisecondsSinceEpoch,
            missed ? 1 : 0,
            nowUtc.millisecondsSinceEpoch,
            expected.taskId,
            expected.remindAt.toIsoString(),
            expected.snoozeUntilUtc?.millisecondsSinceEpoch,
          ],
        );
        return _raw.updatedRows == 1;
      });

  /// Acknowledges a scheduled or notified reminder. Returns whether it changed.
  @override
  bool acknowledge(String taskId, DateTime nowUtc) => _run(() {
    _raw.execute(
      "UPDATE task_reminders SET state = 'acknowledged', snooze_until_utc = NULL, "
      'updated_at_utc = ? WHERE task_id = ? AND state != \'acknowledged\'',
      [nowUtc.millisecondsSinceEpoch, taskId],
    );
    return _raw.updatedRows == 1;
  });

  /// Postpones a reminder until [untilUtc]; it becomes scheduled again.
  @override
  bool snooze(String taskId, DateTime untilUtc, DateTime nowUtc) => _run(() {
    _raw.execute(
      "UPDATE task_reminders SET state = 'scheduled', snooze_until_utc = ?, "
      'notified_at_utc = NULL, missed = 0, updated_at_utc = ? WHERE task_id = ?',
      [untilUtc.millisecondsSinceEpoch, nowUtc.millisecondsSinceEpoch, taskId],
    );
    return _raw.updatedRows == 1;
  });

  /// The title and openness of a task, read from the task table itself (never
  /// from a possibly not yet loaded in-memory workspace). Null when the task
  /// does not exist or has been deleted.
  @override
  ReminderTaskInfo? taskInfo(String taskId) => _run(() {
    final rows = _raw.select(
      'SELECT title, status, deleted_at FROM tasks WHERE id = ?',
      [taskId],
    );
    if (rows.isEmpty || rows.single['deleted_at'] != null) {
      return null;
    }
    final status = rows.single['status'] as String;
    return ReminderTaskInfo(
      title: rows.single['title'] as String,
      open: status != 'done' && status != 'archived',
    );
  });
}
