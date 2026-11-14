import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';

/// Every user-visible string of the reminder feature (English, centralized like
/// [AppStrings]).
abstract final class ReminderStrings {
  static const fieldReminder = 'Reminder';
  static const deviceOnly =
      'Reminders are stored on this device only. They are not synchronized and do not appear on your other devices.';
  static const noReminder = 'No reminder';
  static const setReminder = 'Set reminder';
  static const changeReminder = 'Change';
  static const clearReminder = 'Remove reminder';
  static const acknowledge = 'Done';
  static const snooze = 'Snooze';
  static const snooze10 = '10 minutes';
  static const snooze1h = '1 hour';
  static const snoozeTomorrow = 'Tomorrow 09:00';
  static const openTask = 'Open';
  static const dismissAll = 'Dismiss all';
  static const pickDate = 'Reminder date';
  static const pickTime = 'Reminder time';
  static const errorInPast = 'Choose a time in the future.';
  static const errorUnknownTask = 'This task no longer exists.';
  static const bannerTitle = 'Reminders';
  static const missedTag = 'missed';
  static const nativeUnavailable =
      'Desktop notifications are not available. Reminders appear here.';

  static const notificationTexts = ReminderNotificationTexts(
    dueTitle: 'Nexora reminder',
    missedTitle: 'Nexora: missed reminder',
    summaryTitle: 'Nexora reminders',
    summaryBody: _summary,
  );

  static String _summary(int count) =>
      '$count reminders are due. Open Nexora to see them.';

  static String more(int count) => '+$count more';

  static String errorMessage(ReminderError error) => switch (error) {
    ReminderError.inPast => errorInPast,
    ReminderError.unknownTask => errorUnknownTask,
  };

  static String state(Reminder reminder) => switch (reminder.state) {
    ReminderState.scheduled =>
      reminder.snoozeUntilUtc != null ? 'Snoozed' : 'Scheduled',
    ReminderState.notified => reminder.missed ? 'Due (missed)' : 'Due',
    ReminderState.acknowledged => 'Done',
  };

  static String when(LocalWallTime wall) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${wall.year}-${two(wall.month)}-${two(wall.day)} ${two(wall.hour)}:${two(wall.minute)}';
  }
}
