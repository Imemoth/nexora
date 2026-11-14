import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

/// A fixed zone modelled on America/New_York in 2026: clocks go forward on
/// 2026-03-08 at 02:00 (UTC-5 to UTC-4) and back on 2026-11-01 at 02:00 (UTC-4
/// to UTC-5). "now" is set by tests.
final class FakeZoneClock implements ReminderClock {
  FakeZoneClock(this.now);

  DateTime now;

  static final _dstStart = DateTime.utc(2026, 3, 8, 7);
  static final _dstEnd = DateTime.utc(2026, 11, 1, 6);

  static int offsetHoursAt(DateTime utc) =>
      (!utc.isBefore(_dstStart) && utc.isBefore(_dstEnd)) ? -4 : -5;

  @override
  DateTime nowUtc() => now;

  @override
  LocalWallTime toLocal(DateTime instant) {
    final local = instant.add(Duration(hours: offsetHoursAt(instant)));
    return LocalWallTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  }

  @override
  DateTime resolve(LocalWallTime wall) {
    final asUtc = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    );
    final summer = asUtc.add(const Duration(hours: 4));
    final winter = asUtc.add(const Duration(hours: 5));
    final summerOk = offsetHoursAt(summer) == -4;
    final winterOk = offsetHoursAt(winter) == -5;
    if (summerOk) {
      return summer; // also the first occurrence of an ambiguous time
    }
    if (winterOk) {
      return winter;
    }
    return winter; // inside the skipped hour: the offset before the gap
  }
}

final class RecordedNotification {
  const RecordedNotification(this.taskId, this.title, this.body);

  final String? taskId;
  final String title;
  final String body;
}

final class FakeReminderNotifier implements ReminderNotifier {
  final List<RecordedNotification> shown = [];
  bool result = true;
  bool throwOnShow = false;

  @override
  Future<bool> show({
    required String? taskId,
    required String title,
    required String body,
  }) async {
    if (throwOnShow) {
      throw StateError('channel broken');
    }
    shown.add(RecordedNotification(taskId, title, body));
    return result;
  }
}
