import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';

/// Production clock. Converts the device's local date once, at this edge, so
/// the domain never reads the time zone.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  CalendarDate today() => CalendarDate.fromDateTime(DateTime.now());
}
