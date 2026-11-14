/// A reminder is device-local: it is stored in the local SQLite file of the
/// active workspace and never synchronized (no hosted schema is involved).
///
/// The reminder time is a local wall-clock time ("09:00 on 15 November") with
/// no zone, like an alarm clock. It is converted to an instant only when it is
/// evaluated, by a [ReminderClock], so a change of the system time zone or a
/// daylight-saving switch moves the instant, not the time the user chose.
library;

enum ReminderState {
  /// Waiting for its time (or for its snooze to end).
  scheduled,

  /// The notification was issued and the user has not acknowledged it yet.
  notified,

  /// Handled by the user (or its task was completed or removed).
  acknowledged,
}

/// A local date and time of day with minute precision and no time zone.
final class LocalWallTime implements Comparable<LocalWallTime> {
  const LocalWallTime(this.year, this.month, this.day, this.hour, this.minute);

  factory LocalWallTime.fromDateTime(DateTime local) => LocalWallTime(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
  );

  /// Parses `YYYY-MM-DDTHH:MM`; null when [text] has another shape.
  static LocalWallTime? tryParse(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$')
        .firstMatch(text);
    if (match == null) {
      return null;
    }
    final parts = [for (var i = 1; i <= 5; i++) int.parse(match.group(i)!)];
    final wall = LocalWallTime(
      parts[0],
      parts[1],
      parts[2],
      parts[3],
      parts[4],
    );
    // Reject impossible dates such as 2026-02-30 or 25:99.
    final check = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    );
    final same =
        check.year == wall.year &&
        check.month == wall.month &&
        check.day == wall.day &&
        check.hour == wall.hour &&
        check.minute == wall.minute;
    return same ? wall : null;
  }

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;

  String toIsoString() {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}'
        'T${two(hour)}:${two(minute)}';
  }

  @override
  int compareTo(LocalWallTime other) =>
      toIsoString().compareTo(other.toIsoString());

  @override
  bool operator ==(Object other) =>
      other is LocalWallTime && other.toIsoString() == toIsoString();

  @override
  int get hashCode => toIsoString().hashCode;

  @override
  String toString() => toIsoString();
}

/// Source of "now" and of the wall-clock to instant conversion. Production uses
/// the system zone; tests inject a fixed zone with daylight-saving rules.
abstract interface class ReminderClock {
  DateTime nowUtc();

  /// The instant (UTC) at which the local wall time [wall] occurs.
  ///
  /// A time that does not exist (the hour skipped when clocks go forward)
  /// resolves to the same offset after the gap, so "02:30" becomes 03:30. A time
  /// that occurs twice (clocks go back) resolves to its first occurrence.
  DateTime resolve(LocalWallTime wall);

  /// The local wall time of [instant].
  LocalWallTime toLocal(DateTime instant);
}

/// The device's own time zone.
final class SystemReminderClock implements ReminderClock {
  const SystemReminderClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime resolve(LocalWallTime wall) =>
      DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute).toUtc();

  @override
  LocalWallTime toLocal(DateTime instant) =>
      LocalWallTime.fromDateTime(instant.toLocal());
}

/// One reminder as stored.
final class Reminder {
  const Reminder({
    required this.taskId,
    required this.remindAt,
    required this.state,
    this.snoozeUntilUtc,
    this.notifiedAtUtc,
    this.missed = false,
  });

  final String taskId;
  final LocalWallTime remindAt;
  final ReminderState state;

  /// While set, the reminder fires at this instant instead of [remindAt].
  final DateTime? snoozeUntilUtc;
  final DateTime? notifiedAtUtc;

  /// True when the notification was issued late because the app was not running
  /// (or the device was asleep) at the due time.
  final bool missed;

  /// When the reminder is due.
  DateTime dueUtc(ReminderClock clock) =>
      snoozeUntilUtc ?? clock.resolve(remindAt);

  bool get isPending => state == ReminderState.scheduled;
  bool get needsAcknowledgement => state == ReminderState.notified;
}

/// What the service needs to know about a task to decide on a reminder.
final class ReminderTaskInfo {
  const ReminderTaskInfo({required this.title, required this.open});

  final String title;

  /// False for a done or archived task.
  final bool open;
}

/// Why a reminder change was refused.
enum ReminderError { inPast, unknownTask }
