import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/task_fixtures.dart';

/// The optional time of a due date, against a real SQLite file: storage,
/// restart, migration of existing date-only data, and the proof that the time
/// never enters the synchronization contract (ADR 0004).
const _owner = 'owner-local';
const _date = CalendarDate(2026, 11, 20);

late Directory _dir;
var _n = 0;

String _path() => '${_dir.path}${Platform.pathSeparator}due-${++_n}.db';

SqliteTaskRepository _repo(LocalDatabase db) => SqliteTaskRepository(
  db,
  ownerId: _owner,
  now: () => DateTime.utc(2026, 11, 16, 10),
);

List<Map<String, Object?>> _outbox(LocalDatabase db) => db.raw
    .select('SELECT * FROM sync_outbox ORDER BY rowid')
    .map((r) => {for (final k in r.keys) k: r[k]})
    .toList();

Map<String, Object?> _taskRow(LocalDatabase db, String id) {
  final r = db.raw.select('SELECT * FROM tasks WHERE id = ?', [id]).single;
  return {for (final k in r.keys) k: r[k]};
}

Future<LocalDatabase> _withProject(String path) async {
  final db = LocalDatabase.open(path);
  await _repo(db).saveProject(const Project(id: 'p', name: 'P', position: 0));
  return db;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-due-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('a date-only task keeps no time and survives a restart', () async {
    final path = _path();
    var db = await _withProject(path);
    await _repo(db).saveTask(makeTask(id: 't', projectId: 'p', dueDate: _date));
    db.close();

    db = LocalDatabase.open(path);
    addTearDown(db.close);
    final task = (await _repo(db).loadTasks()).single;
    expect(task.dueDate, _date);
    expect(task.dueTime, isNull); // genuinely date-only, not midnight
    expect(db.raw.select('SELECT * FROM task_due_times'), isEmpty);
  });

  test('a date and time are saved and reopened', () async {
    final path = _path();
    var db = await _withProject(path);
    await _repo(db).saveTask(
      makeTask(
        id: 't',
        projectId: 'p',
        dueDate: _date,
        dueTime: const DueTime(17, 30),
      ),
    );
    db.close();

    db = LocalDatabase.open(path);
    addTearDown(db.close);
    final task = (await _repo(db).loadTasks()).single;
    expect(task.dueDate, _date);
    expect(task.dueTime, const DueTime(17, 30));
    expect(
      _taskRow(db, 't')['due_date'],
      '2026-11-20',
    ); // the column is untouched
  });

  test(
    'a time can be added to, changed on and removed from a saved date',
    () async {
      final db = await _withProject(_path());
      addTearDown(db.close);
      final repo = _repo(db);
      final base = makeTask(id: 't', projectId: 'p', dueDate: _date);
      await repo.saveTask(base);

      await repo.saveTask(base.copyWith(dueTime: const DueTime(8, 0)));
      expect((await repo.loadTasks()).single.dueTime, const DueTime(8, 0));

      await repo.saveTask(base.copyWith(dueTime: const DueTime(21, 15)));
      expect((await repo.loadTasks()).single.dueTime, const DueTime(21, 15));

      await repo.saveTask(base.copyWith(clearDueTime: true));
      final after = (await repo.loadTasks()).single;
      expect(after.dueTime, isNull);
      expect(after.dueDate, _date); // the date stays
      expect(db.raw.select('SELECT * FROM task_due_times'), isEmpty);
    },
  );

  test('clearing the date removes the time', () async {
    final db = await _withProject(_path());
    addTearDown(db.close);
    final repo = _repo(db);
    final timed = makeTask(
      id: 't',
      projectId: 'p',
      dueDate: _date,
      dueTime: const DueTime(9, 0),
    );
    await repo.saveTask(timed);

    await repo.saveTask(timed.copyWith(clearDueDate: true));

    final after = (await repo.loadTasks()).single;
    expect(after.dueDate, isNull);
    expect(after.dueTime, isNull);
    expect(db.raw.select('SELECT * FROM task_due_times'), isEmpty);
  });

  test('a stray time row without a date is ignored on load', () async {
    final db = await _withProject(_path());
    addTearDown(db.close);
    final repo = _repo(db);
    await repo.saveTask(makeTask(id: 't', projectId: 'p'));
    db.raw.execute("INSERT INTO task_due_times VALUES ('t', '10:00')");

    expect((await repo.loadTasks()).single.dueTime, isNull);
  });

  group('the time never enters the synchronization contract', () {
    test('a create patch has no time and the row is unchanged by it', () async {
      final db = await _withProject(_path());
      addTearDown(db.close);
      await _repo(db).saveTask(
        makeTask(
          id: 't',
          projectId: 'p',
          dueDate: _date,
          dueTime: const DueTime(17, 30),
        ),
      );

      final op = _outbox(db).last;
      final patch = jsonDecode(op['payload_json']! as String) as Map;
      final fields = (patch['patch'] ?? patch) as Map;
      expect(fields['due_date'], '2026-11-20'); // the date only
      expect(jsonEncode(patch).contains('17:30'), isFalse);
      expect(jsonEncode(patch).contains('due_time'), isFalse);
    });

    test(
      'a time-only edit writes no outbox operation and keeps the version',
      () async {
        final db = await _withProject(_path());
        addTearDown(db.close);
        final repo = _repo(db);
        final base = makeTask(id: 't', projectId: 'p', dueDate: _date);
        await repo.saveTask(base);
        final outboxBefore = _outbox(db).length;
        final rowBefore = _taskRow(db, 't');

        await repo.saveTask(base.copyWith(dueTime: const DueTime(6, 45)));

        expect(_outbox(db).length, outboxBefore); // nothing to send
        expect(_taskRow(db, 't'), rowBefore); // version, updated_at untouched
      },
    );

    test('a date change with a time sends only the date', () async {
      final db = await _withProject(_path());
      addTearDown(db.close);
      final repo = _repo(db);
      final timed = makeTask(
        id: 't',
        projectId: 'p',
        dueDate: _date,
        dueTime: const DueTime(12, 0),
      );
      await repo.saveTask(timed);

      await repo.saveTask(timed.copyWith(dueDate: _date.addDays(1)));

      final payload = _outbox(db).last['payload_json']! as String;
      expect(payload.contains('2026-11-21'), isTrue);
      expect(payload.contains('due_time'), isFalse);
      expect(payload.contains('12:00'), isFalse);
      expect((await repo.loadTasks()).single.dueTime, const DueTime(12, 0));
    });
  });

  group('migration of existing date-only data', () {
    test('a version 4 file opens at 5 with every task unchanged', () async {
      final path = _path();
      var db = await _withProject(path);
      await _repo(db).saveTask(
        makeTask(id: 'old', projectId: 'p', title: 'Old', dueDate: _date),
      );
      db.close();
      // Step the file back to what version 4 left behind.
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE task_due_times');
      raw.userVersion = 4;
      raw.close();

      db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(db.schemaVersion, 5);
      final task = (await _repo(db).loadTasks()).single;
      expect(task.title, 'Old');
      expect(task.dueDate, _date);
      expect(task.dueTime, isNull);
    });

    test('the table refuses a malformed time', () async {
      final db = await _withProject(_path());
      addTearDown(db.close);
      expect(
        () => db.raw.execute("INSERT INTO task_due_times VALUES ('t', '9:5')"),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
