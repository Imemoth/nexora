/// An optional wall-clock time of day attached to a due date.
///
/// Semantics (see docs/architecture/decisions/0004-due-time-semantics.md):
/// a [DueTime] is a *floating* wall-clock time. It carries no time zone and no
/// UTC offset, and it is never converted. "17:30 on 2026-11-20" means 17:30 on
/// the clock of whoever looks at it, wherever they are. A deadline with a time
/// therefore never moves when the device time zone changes, and a date-only
/// deadline is never given a time.
final class DueTime implements Comparable<DueTime> {
  const DueTime(this.hour, this.minute)
    : assert(hour >= 0 && hour < 24),
      assert(minute >= 0 && minute < 60);

  /// Parses `HH:MM` (24 hour). Returns null for anything else.
  static DueTime? tryParse(String? text) {
    if (text == null) {
      return null;
    }
    final match = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$').firstMatch(text);
    if (match == null) {
      return null;
    }
    return DueTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  final int hour;
  final int minute;

  /// `HH:MM`, 24 hour, zero padded. The stored and sortable form.
  String toHm() {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  int get minutesOfDay => hour * 60 + minute;

  @override
  int compareTo(DueTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is DueTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => toHm();
}
