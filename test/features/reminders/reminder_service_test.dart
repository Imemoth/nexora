import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/reminder_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../support/reminder_support.dart';
import '../../support/task_fixtures.dart';

late Directory _dir;
late String _path;
late FakeZoneClock _clock;
late FakeReminderNotifier _notifier;
final _noon = DateTime.utc(2026, 11, 14, 17); // 12:00 local (UTC-5)
const _later = LocalWallTime(2026, 11, 14, 13, 0);

Future<LocalDatabase> _open({List<String> tasks = const ['t1']}) async {
  final db = LocalDatabase.open(_path);
  final repo = SqliteTaskRepository(db, ownerId: 'o', now: () => _noon);
  await repo.saveProject(const Project(id: 'p1', name: 'P', position: 0));
  for (final id in tasks) {
    await repo.saveTask(makeTask(id: id, title: 'Task $id'));
  }
  return db;
}

ReminderService _service(LocalDatabase db, {int maxIndividual = 3}) {
  return ReminderService(
    store: ReminderStore(db),
    clock: _clock,
    notifier: _notifier,
    maxIndividualNotifications: maxIndividual,
  );
}

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('nexora-remsvc-');
    _path = '${_dir.path}${Platform.pathSeparator}n.db';
    _clock = FakeZoneClock(_noon);
    _notifier = FakeReminderNotifier();
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  test('a reminder in the past is refused, an unknown task too', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    expect(
      s.setReminder('t1', const LocalWallTime(2026, 11, 14, 11, 0)),
      ReminderError.inPast,
    );
    expect(s.setReminder('nope', _later), ReminderError.unknownTask);
    expect(s.reminderFor('t1'), isNull);
  });

  test('nothing fires before the time; it fires once at the time', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    expect(s.setReminder('t1', _later), isNull);

    await s.tick();
    expect(_notifier.shown, isEmpty);

    _clock.now = _noon.add(const Duration(hours: 1)); // 13:00 local
    await s.tick();
    await s.tick();
    await s.tick();
    expect(_notifier.shown, hasLength(1));
    expect(_notifier.shown.single.taskId, 't1');
    expect(_notifier.shown.single.body, 'Task t1');
    expect(s.reminderFor('t1')!.state, ReminderState.notified);
    expect(s.due.single.taskId, 't1');
    expect(s.due.single.missed, isFalse);
  });

  test('a restart never repeats a reminder that was already shown', () async {
    var db = await _open();
    var s = _service(db);
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.start();
    expect(_notifier.shown, hasLength(1));
    s.dispose();
    db.close();

    // "Restart": a new service over the same file.
    db = LocalDatabase.open(_path);
    addTearDown(db.close);
    s = _service(db);
    addTearDown(s.dispose);
    await s.start();
    expect(_notifier.shown, hasLength(1), reason: 'no duplicate notification');
    // The unacknowledged reminder is still in the in-app list.
    expect(s.due.map((d) => d.taskId), ['t1']);
  });

  test('two services racing over one file notify exactly once', () async {
    final db = await _open();
    addTearDown(db.close);
    final a = _service(db);
    final b = _service(db);
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    a.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await Future.wait([a.tick(), b.tick()]);
    expect(_notifier.shown, hasLength(1));
  });

  test(
    'a reminder missed while the app was closed is shown as missed',
    () async {
      var db = await _open();
      var s = _service(db);
      s.setReminder('t1', _later);
      s.dispose();
      db.close();

      _clock.now = _noon.add(const Duration(hours: 5)); // app was closed
      db = LocalDatabase.open(_path);
      addTearDown(db.close);
      s = _service(db);
      addTearDown(s.dispose);
      await s.start();
      expect(_notifier.shown, hasLength(1));
      expect(_notifier.shown.single.title, contains('issed'));
      expect(s.due.single.missed, isTrue);
    },
  );

  test(
    'acknowledge removes it from the list and it never fires again',
    () async {
      final db = await _open();
      addTearDown(db.close);
      final s = _service(db);
      addTearDown(s.dispose);
      s.setReminder('t1', _later);
      _clock.now = _noon.add(const Duration(hours: 1));
      await s.tick();
      s.acknowledge('t1');
      expect(s.due, isEmpty);
      _clock.now = _noon.add(const Duration(days: 2));
      await s.tick();
      expect(_notifier.shown, hasLength(1));
      expect(s.reminderFor('t1')!.state, ReminderState.acknowledged);
    },
  );

  test(
    'snooze postpones, fires again once, then can be acknowledged',
    () async {
      final db = await _open();
      addTearDown(db.close);
      final s = _service(db);
      addTearDown(s.dispose);
      s.setReminder('t1', _later);
      _clock.now = _noon.add(const Duration(hours: 1));
      await s.tick();
      s.snooze('t1', const Duration(minutes: 10));
      expect(s.due, isEmpty);
      expect(s.reminderFor('t1')!.state, ReminderState.scheduled);

      _clock.now = _clock.now.add(const Duration(minutes: 9));
      await s.tick();
      expect(_notifier.shown, hasLength(1));

      _clock.now = _clock.now.add(const Duration(minutes: 2));
      await s.tick();
      expect(_notifier.shown, hasLength(2));
      expect(s.due.single.taskId, 't1');
      s.acknowledge('t1');
      expect(s.due, isEmpty);
    },
  );

  test('snooze until tomorrow morning and a past snooze target', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick();
    expect(
      s.snoozeUntil('t1', const LocalWallTime(2026, 11, 14, 9, 0)),
      ReminderError.inPast,
    );
    expect(
      s.snoozeUntil('t1', const LocalWallTime(2026, 11, 15, 9, 0)),
      isNull,
    );
    expect(s.reminderFor('t1')!.dueUtc(_clock), DateTime.utc(2026, 11, 15, 14));
  });

  test('a snooze survives a restart and fires at its instant', () async {
    var db = await _open();
    var s = _service(db);
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick();
    s.snooze('t1', const Duration(minutes: 30));
    s.dispose();
    db.close();

    db = LocalDatabase.open(_path);
    addTearDown(db.close);
    s = _service(db);
    addTearDown(s.dispose);
    _clock.now = _clock.now.add(const Duration(minutes: 31));
    await s.start();
    expect(_notifier.shown, hasLength(2));
  });

  test('cancel removes the reminder; rescheduling replaces it', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    s.setReminder('t1', _later);
    s.cancel('t1');
    _clock.now = _noon.add(const Duration(hours: 2));
    await s.tick();
    expect(_notifier.shown, isEmpty);

    _clock.now = _noon;
    s.setReminder('t1', _later);
    s.setReminder('t1', const LocalWallTime(2026, 11, 14, 15, 0)); // reschedule
    _clock.now = _noon.add(const Duration(hours: 1, minutes: 30)); // 13:30
    await s.tick();
    expect(_notifier.shown, isEmpty);
    _clock.now = _noon.add(const Duration(hours: 3, minutes: 1));
    await s.tick();
    expect(_notifier.shown, hasLength(1));
  });

  test('rescheduling a fired reminder makes it pending again', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick();
    expect(s.due, hasLength(1));
    expect(
      s.setReminder('t1', const LocalWallTime(2026, 11, 14, 18, 0)),
      isNull,
    );
    expect(s.due, isEmpty);
    expect(s.reminderFor('t1')!.state, ReminderState.scheduled);
  });

  test('a completed task silently drops its reminder', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    s.setReminder('t1', _later);
    final repo = SqliteTaskRepository(db, ownerId: 'o', now: () => _noon);
    await repo.saveTask(
      makeTask(id: 't1', title: 'Task t1', status: TaskStatus.done),
    );
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick();
    expect(_notifier.shown, isEmpty);
    expect(s.reminderFor('t1')!.state, ReminderState.acknowledged);
  });

  test('a fired reminder of a task completed later leaves the list', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick();
    expect(s.due, hasLength(1));
    final repo = SqliteTaskRepository(db, ownerId: 'o', now: () => _noon);
    await repo.saveTask(
      makeTask(id: 't1', title: 'Task t1', status: TaskStatus.done),
    );
    await s.tick();
    expect(s.due, isEmpty);
  });

  test('a failing notification channel never loses the reminder', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    _notifier.throwOnShow = true;
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick(); // must not throw
    expect(
      s.due.single.taskId,
      't1',
      reason: 'the in-app list is the fallback',
    );
  });

  test(
    'native notifications reported as not shown keep the in-app entry',
    () async {
      final db = await _open();
      addTearDown(db.close);
      final s = _service(db);
      addTearDown(s.dispose);
      _notifier.result = false;
      s.setReminder('t1', _later);
      _clock.now = _noon.add(const Duration(hours: 1));
      await s.tick();
      expect(s.due, hasLength(1));
    },
  );

  test('many due reminders are announced with one summary', () async {
    final db = await _open(tasks: ['a', 'b', 'c', 'd', 'e']);
    addTearDown(db.close);
    final s = _service(db);
    addTearDown(s.dispose);
    for (final id in ['a', 'b', 'c', 'd', 'e']) {
      s.setReminder(id, _later);
    }
    _clock.now = _noon.add(const Duration(hours: 1));
    await s.tick();
    expect(_notifier.shown, hasLength(1));
    expect(_notifier.shown.single.taskId, isNull);
    expect(_notifier.shown.single.body, contains('5'));
    expect(s.due, hasLength(5));
  });

  test(
    'spring forward: a reminder inside the skipped hour fires at 03:30',
    () async {
      final db = await _open();
      addTearDown(db.close);
      _clock.now = DateTime.utc(2026, 3, 8, 5); // 00:00 local
      final s = _service(db);
      addTearDown(s.dispose);
      expect(
        s.setReminder('t1', const LocalWallTime(2026, 3, 8, 2, 30)),
        isNull,
      );
      _clock.now = DateTime.utc(2026, 3, 8, 7, 29);
      await s.tick();
      expect(_notifier.shown, isEmpty);
      _clock.now = DateTime.utc(2026, 3, 8, 7, 31);
      await s.tick();
      expect(_notifier.shown, hasLength(1));
    },
  );

  test(
    'fall back: a repeated time fires once, at the first occurrence',
    () async {
      final db = await _open();
      addTearDown(db.close);
      _clock.now = DateTime.utc(2026, 11, 1, 3); // 23:00 local the day before
      final s = _service(db);
      addTearDown(s.dispose);
      s.setReminder('t1', const LocalWallTime(2026, 11, 1, 1, 30));
      _clock.now = DateTime.utc(2026, 11, 1, 5, 31); // 01:31 first time
      await s.tick();
      expect(_notifier.shown, hasLength(1));
      _clock.now = DateTime.utc(2026, 11, 1, 6, 31); // 01:31 second time
      await s.tick();
      expect(_notifier.shown, hasLength(1));
    },
  );

  test('periodic evaluation fires without an explicit tick', () async {
    final db = await _open();
    addTearDown(db.close);
    final s = ReminderService(
      store: ReminderStore(db),
      clock: _clock,
      notifier: _notifier,
      tickInterval: const Duration(milliseconds: 20),
    );
    addTearDown(s.dispose);
    await s.start();
    s.setReminder('t1', _later);
    _clock.now = _noon.add(const Duration(hours: 1));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(_notifier.shown, hasLength(1));
  });

  test(
    'reminders are per workspace file: another file never sees them',
    () async {
      final db = await _open();
      addTearDown(db.close);
      final s = _service(db);
      addTearDown(s.dispose);
      s.setReminder('t1', _later);
      final other = LocalDatabase.open(
        '${_dir.path}${Platform.pathSeparator}o.db',
      );
      addTearDown(other.close);
      expect(ReminderStore(other).all(), isEmpty);
    },
  );
}
