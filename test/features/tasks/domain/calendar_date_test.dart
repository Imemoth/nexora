import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';

void main() {
  group('CalendarDate', () {
    test('orders by year, month, then day', () {
      const earlier = CalendarDate(2026, 11, 10);
      const later = CalendarDate(2026, 11, 11);

      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(earlier), greaterThan(0));
      expect(later.compareTo(const CalendarDate(2026, 11, 11)), 0);
    });

    test('addDays crosses a month boundary', () {
      expect(
        const CalendarDate(2026, 1, 31).addDays(1),
        const CalendarDate(2026, 2, 1),
      );
    });

    test('addDays crosses a year boundary', () {
      expect(
        const CalendarDate(2026, 12, 31).addDays(1),
        const CalendarDate(2027, 1, 1),
      );
    });

    test('addDays handles leap day in a leap year', () {
      expect(
        const CalendarDate(2028, 2, 28).addDays(1),
        const CalendarDate(2028, 2, 29),
      );
      expect(
        const CalendarDate(2028, 2, 28).addDays(2),
        const CalendarDate(2028, 3, 1),
      );
    });

    test('addDays skips leap day in a non-leap year', () {
      expect(
        const CalendarDate(2027, 2, 28).addDays(1),
        const CalendarDate(2027, 3, 1),
      );
    });

    test('addDays accepts negative offsets', () {
      expect(
        const CalendarDate(2026, 3, 1).addDays(-1),
        const CalendarDate(2026, 2, 28),
      );
    });

    test('toIsoString pads month and day', () {
      expect(const CalendarDate(2026, 3, 7).toIsoString(), '2026-03-07');
    });

    test('fromDateTime keeps only the calendar date', () {
      final local = DateTime(2026, 11, 11, 23, 59);

      expect(
        CalendarDate.fromDateTime(local),
        const CalendarDate(2026, 11, 11),
      );
    });

    test('value equality and hashCode', () {
      const a = CalendarDate(2026, 5, 5);
      const b = CalendarDate(2026, 5, 5);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
