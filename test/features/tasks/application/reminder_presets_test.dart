import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/reminder_presets.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

import '../../../support/reminder_support.dart';

/// The fake zone is New York in 2026: clocks go back on 2026-11-01 02:00.
void main() {
  group('presets are relative to now and shown as a concrete wall time', () {
    test('1, 2, 5 and 24 hours from noon', () {
      // 2026-11-14 17:00 UTC is 12:00 local.
      final clock = FakeZoneClock(DateTime.utc(2026, 11, 14, 17));
      expect(
        presetWallTime(clock, ReminderPreset.inOneHour),
        const LocalWallTime(2026, 11, 14, 13, 0),
      );
      expect(
        presetWallTime(clock, ReminderPreset.inTwoHours),
        const LocalWallTime(2026, 11, 14, 14, 0),
      );
      expect(
        presetWallTime(clock, ReminderPreset.inFiveHours),
        const LocalWallTime(2026, 11, 14, 17, 0),
      );
      expect(
        presetWallTime(clock, ReminderPreset.inTwentyFourHours),
        const LocalWallTime(2026, 11, 15, 12, 0),
      );
    });

    test('crossing a day boundary changes the date', () {
      // 23:30 local on 14 Nov.
      final clock = FakeZoneClock(DateTime.utc(2026, 11, 15, 4, 30));
      expect(
        presetWallTime(clock, ReminderPreset.inOneHour),
        const LocalWallTime(2026, 11, 15, 0, 30),
      );
      expect(
        presetWallTime(clock, ReminderPreset.inFiveHours),
        const LocalWallTime(2026, 11, 15, 4, 30),
      );
    });

    test('crossing a month and a year boundary', () {
      // 22:00 local on 31 Dec 2026 (UTC-5).
      final clock = FakeZoneClock(DateTime.utc(2027, 1, 1, 3));
      expect(
        presetWallTime(clock, ReminderPreset.inTwoHours),
        const LocalWallTime(2027, 1, 1, 0, 0),
      );
    });

    test('seconds round up so the result is never before the offset', () {
      final clock = FakeZoneClock(DateTime.utc(2026, 11, 14, 17, 0, 30));
      expect(
        presetWallTime(clock, ReminderPreset.inOneHour),
        const LocalWallTime(2026, 11, 14, 13, 1),
      );
    });

    test('24 hours is elapsed time across a daylight-saving change', () {
      // 20:00 local on 31 Oct (EDT, 00:00 UTC on 1 Nov). Clocks go back during
      // the next 24 hours, so 24 elapsed hours is 19:00 local, not 20:00.
      final clock = FakeZoneClock(DateTime.utc(2026, 11, 1, 0));
      expect(
        presetWallTime(clock, ReminderPreset.inTwentyFourHours),
        const LocalWallTime(2026, 11, 1, 19, 0),
      );
    });

    test('the result is always in the future for the same clock', () {
      final clock = FakeZoneClock(DateTime.utc(2026, 3, 8, 6, 59, 59));
      for (final preset in ReminderPreset.values) {
        final wall = presetWallTime(clock, preset);
        expect(clock.resolve(wall).isAfter(clock.nowUtc()), isTrue);
      }
    });
  });

  group('custom date and time parsing', () {
    test('accepts a date and one- or two-digit hours', () {
      expect(
        parseCustomWallTime('2026-11-20', '7:05'),
        const LocalWallTime(2026, 11, 20, 7, 5),
      );
      expect(
        parseCustomWallTime(' 2026-11-20 ', '17:45'),
        const LocalWallTime(2026, 11, 20, 17, 45),
      );
    });

    test('rejects malformed and impossible values', () {
      for (final (d, t) in [
        ('', '09:00'),
        ('2026-11-20', ''),
        ('20-11-2026', '09:00'),
        ('2026-02-30', '09:00'),
        ('2026-13-01', '09:00'),
        ('2026-11-20', '24:00'),
        ('2026-11-20', '09:60'),
        ('2026-11-20', '9'),
      ]) {
        expect(parseCustomWallTime(d, t), isNull, reason: '$d $t');
      }
    });
  });
}
