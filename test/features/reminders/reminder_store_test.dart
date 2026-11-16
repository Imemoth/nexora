import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/reminder_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/task_fixtures.dart';
import '../../support/v1_database.dart';

late Directory _dir;
var _counter = 0;

String _path() => '${_dir.path}${Platform.pathSeparator}r-${_counter++}.db';

final _t0 = DateTime.utc(2026, 11, 14, 10);
const _wall = LocalWallTime(2026, 11, 15, 9, 0);

Future<LocalDatabase> _dbWithTask(String path, {String id = 't1'}) async {
  final db = LocalDatabase.open(path);
  final repo = SqliteTaskRepository(db, ownerId: 'o', now: () => _t0);
  await repo.saveProject(const Project(id: 'p1', name: 'P', position: 0));
  await repo.saveTask(makeTask(id: id, title: 'Pay rent'));
  return db;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-rem-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('schema version 5 (reminder table since 4)', () {
    test('a new file has the reminder table', () {
      final db = LocalDatabase.open(_path());
      addTearDown(db.close);
      expect(LocalDatabase.currentVersion, 5);
      final tables = db.raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'])
          .toSet();
      expect(tables, contains('task_reminders'));
    });

    test('a version 3 file keeps every row when migrated', () async {
      final path = _path();
      final db = await _dbWithTask(path);
      db.close();
      // Step the file back to version 3: no reminder table, nothing else.
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE task_reminders');
      raw.execute('DROP TABLE task_due_times');
      raw.userVersion = 3;
      raw.close();

      final migrated = LocalDatabase.open(path);
      addTearDown(migrated.close);
      expect(migrated.schemaVersion, 5);
      expect(
        migrated.raw.select('SELECT title FROM tasks').single['title'],
        'Pay rent',
      );
      expect(ReminderStore(migrated).all(), isEmpty);
    });

    test('a version 1 file is migrated through every version to 5', () {
      final path = _path();
      createV1File(path);
      final db = LocalDatabase.open(path);
      addTearDown(db.close);
      expect(db.schemaVersion, 5);
      expect(ReminderStore(db).all(), isEmpty);
    });

    test('a newer file is still refused', () {
      final path = _path();
      LocalDatabase.open(path).close();
      final raw = sqlite3.open(path);
      raw.userVersion = 6;
      raw.close();
      expect(() => LocalDatabase.open(path), throwsA(anything));
    });
  });

  group('reminder store', () {
    test('schedule, read, replace and cancel', () async {
      final db = await _dbWithTask(_path());
      addTearDown(db.close);
      final store = ReminderStore(db);
      store.schedule('t1', _wall, _t0);
      final r = store.get('t1')!;
      expect(r.remindAt, _wall);
      expect(r.state, ReminderState.scheduled);

      store.schedule('t1', const LocalWallTime(2026, 11, 16, 8, 30), _t0);
      expect(store.all(), hasLength(1));
      expect(store.get('t1')!.remindAt.hour, 8);

      expect(store.cancel('t1'), isTrue);
      expect(store.get('t1'), isNull);
      expect(store.cancel('t1'), isFalse);
    });

    test('claim succeeds once for exactly one caller', () async {
      final db = await _dbWithTask(_path());
      addTearDown(db.close);
      final store = ReminderStore(db);
      store.schedule('t1', _wall, _t0);
      final seen = store.get('t1')!;
      expect(store.claim(seen, _t0, missed: false), isTrue);
      expect(store.claim(seen, _t0, missed: false), isFalse);
      expect(store.get('t1')!.state, ReminderState.notified);
    });

    test('a claim of an edited reminder is refused', () async {
      final db = await _dbWithTask(_path());
      addTearDown(db.close);
      final store = ReminderStore(db);
      store.schedule('t1', _wall, _t0);
      final stale = store.get('t1')!;
      store.schedule('t1', const LocalWallTime(2026, 12, 1, 9, 0), _t0);
      expect(store.claim(stale, _t0, missed: false), isFalse);
      expect(store.get('t1')!.state, ReminderState.scheduled);
    });

    test('snooze returns to scheduled with its own instant', () async {
      final db = await _dbWithTask(_path());
      addTearDown(db.close);
      final store = ReminderStore(db);
      store.schedule('t1', _wall, _t0);
      store.claim(store.get('t1')!, _t0, missed: true);
      final until = _t0.add(const Duration(minutes: 10));
      expect(store.snooze('t1', until, _t0), isTrue);
      final r = store.get('t1')!;
      expect(r.state, ReminderState.scheduled);
      expect(r.snoozeUntilUtc, until);
      expect(r.missed, isFalse);
    });

    test('acknowledge is idempotent', () async {
      final db = await _dbWithTask(_path());
      addTearDown(db.close);
      final store = ReminderStore(db);
      store.schedule('t1', _wall, _t0);
      expect(store.acknowledge('t1', _t0), isTrue);
      expect(store.acknowledge('t1', _t0), isFalse);
      expect(store.get('t1')!.state, ReminderState.acknowledged);
    });

    test('state survives closing and reopening the file', () async {
      final path = _path();
      var db = await _dbWithTask(path);
      var store = ReminderStore(db);
      store.schedule('t1', _wall, _t0);
      store.claim(store.get('t1')!, _t0, missed: false);
      db.close();

      db = LocalDatabase.open(path);
      addTearDown(db.close);
      store = ReminderStore(db);
      expect(store.get('t1')!.state, ReminderState.notified);
    });

    test(
      'the task table is the source of a task\'s title and openness',
      () async {
        final db = await _dbWithTask(_path());
        addTearDown(db.close);
        final store = ReminderStore(db);
        expect(store.taskInfo('t1')!.title, 'Pay rent');
        expect(store.taskInfo('t1')!.open, isTrue);
        expect(store.taskInfo('missing'), isNull);

        final repo = SqliteTaskRepository(db, ownerId: 'o', now: () => _t0);
        await repo.saveTask(
          makeTask(id: 't1', title: 'Pay rent', status: TaskStatus.done),
        );
        expect(store.taskInfo('t1')!.open, isFalse);
        db.raw.execute("UPDATE tasks SET deleted_at = 'x' WHERE id = 't1'");
        expect(store.taskInfo('t1'), isNull);
      },
    );

    test('the table refuses a malformed wall time', () async {
      final db = await _dbWithTask(_path());
      addTearDown(db.close);
      db.raw.execute(
        "INSERT INTO task_reminders (task_id, remind_at_local, state, missed, updated_at_utc) "
        "VALUES ('t1', '2026-11-15T09:00', 'scheduled', 0, 1)",
      );
      expect(ReminderStore(db).all(), hasLength(1));
      expect(
        () => db.raw.execute(
          "INSERT INTO task_reminders (task_id, remind_at_local, state, missed, updated_at_utc) "
          "VALUES ('t2', 'garbage', 'scheduled', 0, 1)",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
