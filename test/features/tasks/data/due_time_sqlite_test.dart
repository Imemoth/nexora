import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/entity_patch.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/due_time.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/task_fixtures.dart';

/// The optional time of a due date in the local file (schema 6, ADR 0004): storage,
/// restart, migration from every earlier version, and what a synchronized task puts
/// on the wire.
const _owner = 'owner-local';
const _date = CalendarDate(2026, 11, 20);

late Directory _dir;
var _n = 0;

String _path() => '${_dir.path}${Platform.pathSeparator}due-${++_n}.db';

SqliteTaskRepository _repo(LocalDatabase db, {bool Function()? syncs}) =>
    SqliteTaskRepository(
      db,
      ownerId: _owner,
      now: () => DateTime.utc(2026, 11, 16, 10),
      dueTimeSyncs: syncs,
    );

List<Map<String, Object?>> _outbox(LocalDatabase db) => db.raw
    .select('SELECT * FROM sync_outbox ORDER BY rowid')
    .map((r) => {for (final k in r.keys) k: r[k]})
    .toList();

Map<String, Object?> _lastPatch(LocalDatabase db) {
  final json = jsonDecode(_outbox(db).last['payload_json']! as String) as Map;
  return Map<String, Object?>.from((json['patch'] ?? json) as Map);
}

Map<String, Object?> _taskRow(LocalDatabase db, String id) {
  final r = db.raw.select('SELECT * FROM tasks WHERE id = ?', [id]).single;
  return {for (final k in r.keys) k: r[k]};
}

/// Sends and acknowledges everything pending (as the engine would), so the next
/// edit is a new patch-only operation against the acknowledged version.
void _acknowledgeAll(LocalDatabase db) {
  final store = OutboxStore(db);
  var version = 0;
  for (;;) {
    final batch = store.claimBatch();
    if (batch.isEmpty) {
      return;
    }
    version++;
    store.acknowledge(
      [batch.single.operationId],
      [
        {
          'operation_id': batch.single.operationId,
          'status': 'applied',
          'version_before': 0,
          'applied_version': version,
          'row': {'version': version},
          'replayed': false,
        },
      ],
    );
  }
}

Future<LocalDatabase> _withProject(String path) async {
  final db = LocalDatabase.open(path);
  await _repo(db).saveProject(const Project(id: 'p', name: 'P', position: 0));
  return db;
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-due-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('storage', () {
    test('a date-only task keeps no time and survives a restart', () async {
      final path = _path();
      var db = await _withProject(path);
      await _repo(db)
          .saveTask(makeTask(id: 't', projectId: 'p', dueDate: _date));
      db.close();
      db = LocalDatabase.open(path);
      addTearDown(db.close);
      final task = (await _repo(db).loadTasks()).single;
      expect(task.dueDate, _date);
      expect(task.dueTime, isNull); // genuinely date-only, never midnight
      expect(_taskRow(db, 't')['due_time'], isNull);
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
      expect((task.dueDate, task.dueTime), (_date, const DueTime(17, 30)));
      expect(_taskRow(db, 't')['due_time'], '17:30');
      expect(_taskRow(db, 't')['due_date'], '2026-11-20');
    });

    test('a time can be added, changed and removed; the date stays', () async {
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
      expect((after.dueDate, after.dueTime), (_date, null));
    });

    test('midnight is a real time, not the absence of one', () async {
      final db = await _withProject(_path());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveTask(
        makeTask(
          id: 't',
          projectId: 'p',
          dueDate: _date,
          dueTime: const DueTime(0, 0),
        ),
      );
      expect(_taskRow(db, 't')['due_time'], '00:00');
      expect((await repo.loadTasks()).single.dueTime, const DueTime(0, 0));
    });

    test('clearing the date clears the time', () async {
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
      expect((after.dueDate, after.dueTime), (null, null));
      expect(_taskRow(db, 't')['due_time'], isNull);
    });

    test(
      'the file itself refuses a time without a date and malformed times',
      () async {
        final db = await _withProject(_path());
        addTearDown(db.close);
        await _repo(db).saveTask(makeTask(id: 't', projectId: 'p'));
        for (final sql in [
          "UPDATE tasks SET due_time = '10:00' WHERE id = 't'", // no date
          "UPDATE tasks SET due_date = '2026-11-20', due_time = '9:5' WHERE id = 't'",
          "UPDATE tasks SET due_date = '2026-11-20', due_time = '24:00' WHERE id = 't'",
          "UPDATE tasks SET due_date = '2026-11-20', due_time = '10:00:30' WHERE id = 't'",
        ]) {
          expect(
            () => db.raw.execute(sql),
            throwsA(isA<SqliteException>()),
            reason: sql,
          );
        }
      },
    );
  });

  group('migration', () {
    Future<String> versionFiveFile({required bool withStray}) async {
      final path = _path();
      final db = await _withProject(path);
      await _repo(db).saveTask(
        makeTask(id: 'dated', projectId: 'p', title: 'Dated', dueDate: _date),
      );
      await _repo(db)
          .saveTask(makeTask(id: 'undated', projectId: 'p', title: 'Undated'));
      db.close();
      // Rebuild what a version 5 file looked like: no column, the side table.
      final raw = sqlite3.open(path);
      raw.execute('ALTER TABLE tasks DROP COLUMN due_time');
      raw.execute(
        "CREATE TABLE task_due_times (task_id TEXT NOT NULL PRIMARY KEY, due_time TEXT NOT NULL CHECK (due_time GLOB '[0-2][0-9]:[0-5][0-9]'))",
      );
      raw.execute("INSERT INTO task_due_times VALUES ('dated', '17:30')");
      if (withStray) {
        raw.execute("INSERT INTO task_due_times VALUES ('undated', '08:00')");
      }
      raw.userVersion = 5;
      raw.close();
      return path;
    }

    test('a version 5 file keeps its times, moves them into the column and drops the side table', () async {
      final db = LocalDatabase.open(await versionFiveFile(withStray: false));
      addTearDown(db.close);
      expect(db.schemaVersion, 6);
      final tasks = {for (final t in await _repo(db).loadTasks()) t.id: t};
      expect(tasks['dated']!.dueTime, const DueTime(17, 30));
      expect(tasks['dated']!.dueDate, _date);
      expect(tasks['undated']!.dueTime, isNull);
      expect(
        db.raw.select(
          "SELECT name FROM sqlite_master WHERE name = 'task_due_times'",
        ),
        isEmpty,
      );
    });

    test('a stray version 5 time without a date is discarded, never attached to nothing', () async {
      final db = LocalDatabase.open(await versionFiveFile(withStray: true));
      addTearDown(db.close);
      expect(_taskRow(db, 'undated')['due_time'], isNull);
      expect(_taskRow(db, 'undated')['due_date'], isNull);
    });

    test(
      'a version 4 file (date-only tasks) opens at 6 with every task unchanged',
      () async {
        final path = _path();
        var db = await _withProject(path);
        await _repo(db).saveTask(
          makeTask(id: 'old', projectId: 'p', title: 'Old', dueDate: _date),
        );
        db.close();
        final raw = sqlite3.open(path);
        raw.execute('ALTER TABLE tasks DROP COLUMN due_time');
        raw.userVersion = 4;
        raw.close();
        db = LocalDatabase.open(path);
        addTearDown(db.close);
        expect(db.schemaVersion, 6);
        final task = (await _repo(db).loadTasks()).single;
        expect((task.title, task.dueDate, task.dueTime), ('Old', _date, null));
      },
    );

    test('a failed migration leaves the version 5 file as it was', () async {
      final path = await versionFiveFile(withStray: false);
      final raw = sqlite3.open(path);
      raw.execute(
        "INSERT INTO task_due_times VALUES ('dated', '17:30') ON CONFLICT DO NOTHING",
      );
      raw.execute('DROP TABLE task_due_times'); // makes the copy step fail
      raw.close();
      expect(
        () => LocalDatabase.open(path),
        throwsA(isA<RepositoryException>()),
      );
      final check = sqlite3.open(path);
      addTearDown(check.close);
      expect(check.userVersion, 5);
    });
  });

  group('what a synchronized task puts on the wire', () {
    Future<LocalDatabase> synced({bool Function()? syncs}) async {
      final db = await _withProject(_path());
      addTearDown(db.close);
      return db;
    }

    test('a create with a time carries it with its date', () async {
      final db = await synced();
      await _repo(db).saveTask(
        makeTask(
          id: 't',
          projectId: 'p',
          dueDate: _date,
          dueTime: const DueTime(17, 30),
        ),
      );
      final patch = _lastPatch(db);
      expect(patch['due_date'], '2026-11-20');
      expect(patch['due_time'], '17:30');
    });

    test('a date-only create never mentions a time', () async {
      final db = await synced();
      await _repo(db)
          .saveTask(makeTask(id: 't', projectId: 'p', dueDate: _date));
      expect(_lastPatch(db).containsKey('due_time'), isFalse);
    });

    test(
      'a time-only edit sends only the time, with the base version',
      () async {
        final db = await synced();
        final repo = _repo(db);
        final base = makeTask(id: 't', projectId: 'p', dueDate: _date);
        await repo.saveTask(base);
        _acknowledgeAll(db);
        await repo.saveTask(base.copyWith(dueTime: const DueTime(6, 45)));
        expect(_lastPatch(db), {'due_time': '06:45'});
      },
    );

    test('clearing the time sends an explicit null', () async {
      final db = await synced();
      final repo = _repo(db);
      final timed = makeTask(
        id: 't',
        projectId: 'p',
        dueDate: _date,
        dueTime: const DueTime(9, 0),
      );
      await repo.saveTask(timed);
      _acknowledgeAll(db);
      await repo.saveTask(timed.copyWith(clearDueTime: true));
      expect(_lastPatch(db), {'due_time': null});
    });

    test(
      'moving the date of a timed task sends the time as well (kept)',
      () async {
        final db = await synced();
        final repo = _repo(db);
        final timed = makeTask(
          id: 't',
          projectId: 'p',
          dueDate: _date,
          dueTime: const DueTime(9, 0),
        );
        await repo.saveTask(timed);
        _acknowledgeAll(db);
        await repo.saveTask(timed.copyWith(dueDate: _date.addDays(3)));
        expect(_lastPatch(db), {'due_date': '2026-11-23', 'due_time': '09:00'});
      },
    );

    test('moving the date of a date-only task sends no time', () async {
      final db = await synced();
      final repo = _repo(db);
      final base = makeTask(id: 't', projectId: 'p', dueDate: _date);
      await repo.saveTask(base);
      _acknowledgeAll(db);
      await repo.saveTask(base.copyWith(dueDate: _date.addDays(1)));
      expect(_lastPatch(db), {'due_date': '2026-11-21'});
    });

    test(
      'without server support a new time is refused, and dates still sync',
      () async {
        final db = await synced();
        final repo = _repo(db, syncs: () => false);
        final base = makeTask(id: 't', projectId: 'p', dueDate: _date);
        await repo.saveTask(base);
        await expectLater(
          repo.saveTask(base.copyWith(dueTime: const DueTime(9, 0))),
          throwsA(isA<RepositoryException>()),
        );
        expect(_taskRow(db, 't')['due_time'], isNull);
        _acknowledgeAll(db);
        await repo.saveTask(base.copyWith(dueDate: _date.addDays(1)));
        expect(_lastPatch(db), {'due_date': '2026-11-21'});
      },
    );
  });

  group('patch helpers', () {
    test('normalizeDueTime accepts the wire and the PostgreSQL form only', () {
      expect(normalizeDueTime('17:30'), '17:30');
      expect(normalizeDueTime('17:30:00'), '17:30');
      expect(normalizeDueTime('17:30:30'), isNull);
      expect(normalizeDueTime('7:30'), isNull);
      expect(normalizeDueTime(null), isNull);
      expect(normalizeDueTime(1730), isNull);
    });

    test('changedFields compares the time in its normalized form', () {
      final same = changedFields(
        'task',
        {'due_date': '2026-11-20', 'due_time': '17:30'},
        {'due_date': '2026-11-20', 'due_time': '17:30:00'},
      );
      expect(same, isEmpty);
    });

    test('changedFields pairs the time with a changed date', () {
      final patch = changedFields(
        'task',
        {'due_date': '2026-11-25', 'due_time': '17:30'},
        {'due_date': '2026-11-20', 'due_time': '17:30:00'},
      );
      expect(patch, {'due_date': '2026-11-25', 'due_time': '17:30'});
    });

    test('createPatchFromRow never sends a time without a date', () {
      final patch = createPatchFromRow('task', {
        'project_id': 'p',
        'title': 't',
        'status': 'open',
        'priority': 'none',
        'sort_order': 0,
        'due_date': null,
        'due_time': '10:00',
      });
      expect(patch.containsKey('due_time'), isFalse);
    });
  });
}
