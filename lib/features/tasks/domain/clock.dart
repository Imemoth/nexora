import 'calendar_date.dart';

/// Source of the current local date. Production wiring uses the system clock;
/// tests inject a fixed date so smart views are deterministic.
abstract interface class Clock {
  CalendarDate today();
}
