import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';

final class FixedClock implements Clock {
  const FixedClock(this._today);

  final CalendarDate _today;

  @override
  CalendarDate today() {
    return _today;
  }
}
