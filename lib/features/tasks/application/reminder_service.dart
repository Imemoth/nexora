import 'dart:async';

import 'package:nexora/features/tasks/domain/reminder.dart';

/// Persistence needed by the service (implemented by `ReminderStore`).
abstract interface class ReminderPersistence {
  Reminder? get(String taskId);
  List<Reminder> all();
  void schedule(String taskId, LocalWallTime wall, DateTime nowUtc);
  bool cancel(String taskId);
  bool claim(Reminder expected, DateTime nowUtc, {required bool missed});
  bool acknowledge(String taskId, DateTime nowUtc);
  bool snooze(String taskId, DateTime untilUtc, DateTime nowUtc);
  ReminderTaskInfo? taskInfo(String taskId);
}

/// Shows a notification outside the window. Returns false when it could not be
/// shown; the in-app reminder list is the fallback and is always available.
abstract interface class ReminderNotifier {
  /// [taskId] is null for a summary of several reminders.
  Future<bool> show({
    required String? taskId,
    required String title,
    required String body,
  });
}

/// A reminder that is shown in the in-app list (notified, not acknowledged).
final class DueReminder {
  const DueReminder({
    required this.reminder,
    required this.title,
    required this.missed,
  });

  final Reminder reminder;
  final String title;
  final bool missed;

  String get taskId => reminder.taskId;
}

/// Short, user-visible texts of the notification. Kept here (no widgets) and
/// overridable so the strings stay in one place with the other app strings.
final class ReminderNotificationTexts {
  const ReminderNotificationTexts({
    this.dueTitle = 'Reminder',
    this.missedTitle = 'Missed reminder',
    this.summaryTitle = 'Nexora reminders',
    this.summaryBody = _summaryBody,
  });

  final String dueTitle;
  final String missedTitle;
  final String summaryTitle;
  final String Function(int count) summaryBody;

  static String _summaryBody(int count) =>
      '$count reminders are due. Open Nexora to see them.';
}

/// Schedules, fires, snoozes and acknowledges reminders for one workspace.
///
/// Firing is evaluated on a short periodic tick and on every change, never from
/// one long timer, so a system clock change, a daylight-saving switch, a sleep
/// or a resume is picked up within one tick. A due reminder is claimed in
/// SQLite (committed) before its notification is shown: a restart therefore
/// never shows the same reminder twice, and a reminder whose notification could
/// not be shown stays in the in-app list until acknowledged.
final class ReminderService {
  ReminderService({
    required this._store,
    required this._clock,
    required this._notifier,
    this.tickInterval = const Duration(seconds: 15),
    this.missedAfter = const Duration(minutes: 2),
    this.maxIndividualNotifications = 3,
    this.texts = const ReminderNotificationTexts(),
  });

  final ReminderPersistence _store;
  final ReminderClock _clock;
  final ReminderNotifier _notifier;
  final Duration tickInterval;

  /// A reminder shown later than this after its due time counts as missed.
  final Duration missedAfter;

  /// More due reminders than this in one tick are announced with one summary.
  final int maxIndividualNotifications;
  final ReminderNotificationTexts texts;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Timer? _timer;
  bool _ticking = false;
  bool _disposed = false;
  List<DueReminder> _due = const [];

  /// Emits after every change of a reminder or of the in-app list.
  Stream<void> get changes => _changes.stream;

  ReminderClock get clock => _clock;

  /// Reminders that fired and are waiting for the user.
  List<DueReminder> get due => _due;

  Reminder? reminderFor(String taskId) => _store.get(taskId);

  /// Reminders still waiting for their time (including snoozed ones), earliest
  /// first, for the dashboard's reminder panel.
  List<DueReminder> get scheduled {
    final result = <DueReminder>[];
    for (final reminder in _store.all()) {
      if (reminder.state != ReminderState.scheduled) {
        continue;
      }
      final info = _store.taskInfo(reminder.taskId);
      if (info == null) {
        continue;
      }
      result.add(
        DueReminder(reminder: reminder, title: info.title, missed: false),
      );
    }
    return result;
  }

  /// Evaluates once now (this is what handles reminders missed while the app was
  /// closed) and then keeps evaluating every [tickInterval].
  Future<void> start() async {
    _timer ??= Timer.periodic(tickInterval, (_) => unawaited(tick()));
    await tick();
  }

  /// One evaluation: fire due reminders, drop reminders of finished or removed
  /// tasks, refresh the in-app list.
  Future<void> tick() async {
    if (_ticking || _disposed) {
      return;
    }
    _ticking = true;
    try {
      final now = _clock.nowUtc();
      final toFire = <(Reminder, ReminderTaskInfo, bool)>[];
      for (final reminder in _store.all()) {
        if (reminder.state == ReminderState.acknowledged) {
          continue;
        }
        final info = _store.taskInfo(reminder.taskId);
        if (info == null || !info.open) {
          // The task is done, archived or gone: nothing left to remind about.
          _store.acknowledge(reminder.taskId, now);
          continue;
        }
        if (reminder.state != ReminderState.scheduled) {
          continue;
        }
        final dueAt = reminder.dueUtc(_clock);
        if (dueAt.isAfter(now)) {
          continue;
        }
        final missed = now.difference(dueAt) > missedAfter;
        if (_store.claim(reminder, now, missed: missed)) {
          toFire.add((reminder, info, missed));
        }
      }
      _refreshDue();
      if (toFire.isNotEmpty) {
        await _announce(toFire);
      }
    } finally {
      _ticking = false;
    }
  }

  Future<void> _announce(List<(Reminder, ReminderTaskInfo, bool)> fired) async {
    try {
      if (fired.length > maxIndividualNotifications) {
        await _notifier.show(
          taskId: null,
          title: texts.summaryTitle,
          body: texts.summaryBody(fired.length),
        );
        return;
      }
      for (final (reminder, info, missed) in fired) {
        await _notifier.show(
          taskId: reminder.taskId,
          title: missed ? texts.missedTitle : texts.dueTitle,
          body: info.title,
        );
      }
    } on Object {
      // A failing notification channel must never break scheduling: the
      // reminder is already recorded as notified and stays in the in-app list.
    }
  }

  void _refreshDue() {
    final next = <DueReminder>[];
    for (final reminder in _store.all()) {
      if (reminder.state != ReminderState.notified) {
        continue;
      }
      final info = _store.taskInfo(reminder.taskId);
      if (info == null) {
        continue;
      }
      next.add(
        DueReminder(
          reminder: reminder,
          title: info.title,
          missed: reminder.missed,
        ),
      );
    }
    _due = next;
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// Sets (or replaces) the reminder of [taskId]. Returns null on success.
  ReminderError? setReminder(String taskId, LocalWallTime wall) {
    final info = _store.taskInfo(taskId);
    if (info == null) {
      return ReminderError.unknownTask;
    }
    final now = _clock.nowUtc();
    if (!_clock.resolve(wall).isAfter(now)) {
      return ReminderError.inPast;
    }
    _store.schedule(taskId, wall, now);
    _refreshDue();
    return null;
  }

  /// Removes the reminder (cancellation).
  void cancel(String taskId) {
    _store.cancel(taskId);
    _refreshDue();
  }

  /// Marks a fired reminder as handled.
  void acknowledge(String taskId) {
    _store.acknowledge(taskId, _clock.nowUtc());
    _refreshDue();
  }

  /// Postpones the reminder by [by] from now.
  void snooze(String taskId, Duration by) {
    final now = _clock.nowUtc();
    _store.snooze(taskId, now.add(by), now);
    _refreshDue();
  }

  /// Postpones the reminder to the local wall time [wall] (for example tomorrow
  /// morning). A time in the past is refused.
  ReminderError? snoozeUntil(String taskId, LocalWallTime wall) {
    final now = _clock.nowUtc();
    final until = _clock.resolve(wall);
    if (!until.isAfter(now)) {
      return ReminderError.inPast;
    }
    _store.snooze(taskId, until, now);
    _refreshDue();
    return null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_changes.close());
  }
}
