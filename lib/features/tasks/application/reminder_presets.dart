import 'package:nexora/features/tasks/domain/reminder.dart';

/// The quick choices of the reminder dialog.
enum ReminderPreset {
  inOneHour(Duration(hours: 1)),
  inTwoHours(Duration(hours: 2)),
  inFiveHours(Duration(hours: 5)),
  inTwentyFourHours(Duration(hours: 24));

  const ReminderPreset(this.offset);

  /// Elapsed time from now (real hours, not wall-clock hours).
  final Duration offset;
}

/// The wall time a preset resolves to for the clock's current instant.
///
/// The offset is added to the instant, not to the wall clock, so "In 24 hours"
/// is 24 elapsed hours even across a daylight-saving change (the wall time then
/// differs from "same time tomorrow" by an hour). Seconds round up to the next
/// minute so the result is never earlier than the stated offset.
LocalWallTime presetWallTime(ReminderClock clock, ReminderPreset preset) {
  var instant = clock.nowUtc().add(preset.offset);
  if (instant.second != 0 ||
      instant.millisecond != 0 ||
      instant.microsecond != 0) {
    instant = DateTime.utc(
      instant.year,
      instant.month,
      instant.day,
      instant.hour,
      instant.minute,
    ).add(const Duration(minutes: 1));
  }
  return clock.toLocal(instant);
}

/// Parses the custom date (`YYYY-MM-DD`) and time (`H:MM` or `HH:MM`) fields
/// into a wall time. Null when either is malformed or the date does not exist.
LocalWallTime? parseCustomWallTime(String date, String time) {
  final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date.trim());
  final t = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
  if (d == null || t == null) {
    return null;
  }
  String two(int v) => v.toString().padLeft(2, '0');
  return LocalWallTime.tryParse(
    '${d.group(1)}-${d.group(2)}-${d.group(3)}'
    'T${two(int.parse(t.group(1)!))}:${t.group(2)}',
  );
}
