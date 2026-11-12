/// A calendar date with no time and no time zone.
///
/// Phase 1 deadlines are date-only. Conversion from [DateTime] happens only at
/// the edge (see Clock), so rules never depend on the device time zone.
final class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  factory CalendarDate.fromDateTime(DateTime local) {
    return CalendarDate(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  /// Returns the date [days] after this one. Negative values go backwards.
  CalendarDate addDays(int days) {
    final shifted = DateTime.utc(year, month, day + days);
    return CalendarDate(shifted.year, shifted.month, shifted.day);
  }

  /// ISO 8601 calendar date, for example 2026-03-07.
  String toIsoString() {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  int compareTo(CalendarDate other) {
    final byYear = year.compareTo(other.year);
    if (byYear != 0) {
      return byYear;
    }
    final byMonth = month.compareTo(other.month);
    if (byMonth != 0) {
      return byMonth;
    }
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) {
    return other is CalendarDate &&
        other.year == year &&
        other.month == month &&
        other.day == day;
  }

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIsoString();
}
