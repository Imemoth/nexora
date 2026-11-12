import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/task_fixtures.dart';

/// Integration tests against a real temporary SQLite file. Each test gets its
/// own database. Closing and reopening the file simulates a restart.
const _owner = 'owner-local';

late Directory _dir;
var _fileCounter = 0;

String _newPath() {
  _fileCounter++;
  return '${_dir.path}${Platform.pathSeparator}nexora-$_fileCounter.db';
}

DateTime _clockAt(int minute) => DateTime.utc(2026, 11, 12, 10, minute);

SqliteTaskRepository _repo(LocalDatabase db, {int minute = 0}) {
  return SqliteTaskRepository(db, ownerId: _owner, now: () => _clockAt(minute));
}

/// Reads rows through the raw handle, so the tests do not depend on production
/// helpers.
List<Map<String, Object?>> _rows(
  LocalDatabase db,
  String table,
  String column,
  Object value,
) {
  return db.raw
      .select('SELECT * FROM $table WHERE $column = ?', [value])
      .map((row) => {for (final key in row.keys) key: row[key]})
      .toList();
}

List<Map<String, Object?>> _outbox(LocalDatabase db) {
  return db.raw
      .select('SELECT * FROM sync_outbox ORDER BY rowid')
      .map((row) => {for (final key in row.keys) key: row[key]})
      .toList();
}

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('nexora-sqlite-test-');
  });

  tearDown(() {
    _dir.deleteSync(recursive: true);
  });

  group('schema and migrations', () {
    test('a new file is migrated to the current schema version', () {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);

      expect(db.schemaVersion, LocalDatabase.currentVersion);
      final tables = db.raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(tables.contains('projects'), isTrue);
      expect(tables.contains('tasks'), isTrue);
      expect(tables.contains('sync_outbox'), isTrue);
      expect(tables.contains('meta'), isTrue);
    });

    test('reopening a migrated file keeps its version', () {
      final path = _newPath();
      LocalDatabase.open(path).close();

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(db.schemaVersion, LocalDatabase.currentVersion);
    });

    test(
      'a file written by a newer app version is refused and left unchanged',
      () {
        final path = _newPath();
        LocalDatabase.open(path).close();
        final raw = sqlite3.open(path);
        raw.userVersion = LocalDatabase.currentVersion + 1;
        raw.dispose();

        expect(
          () => LocalDatabase.open(path),
          throwsA(isA<RepositoryException>()),
        );

        final check = sqlite3.open(path);
        addTearDown(check.dispose);
        expect(check.userVersion, LocalDatabase.currentVersion + 1);
      },
    );
  });

  group('projects', () {
    test('a project round-trips with its owner and position', () async {
      final path = _newPath();
      final db = LocalDatabase.open(path);
      await _repo(db)
          .saveProject(const Project(id: 'p-home', name: 'Home', position: 3));
      db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final projects = await _repo(reopened).loadProjects();

      expect(projects, hasLength(1));
      expect(projects.single.id, 'p-home');
      expect(projects.single.name, 'Home');
      expect(projects.single.position, 3);
      expect(
        _rows(reopened, 'projects', 'id', 'p-home').single['owner_id'],
        _owner,
      );
    });
  });

  group('tasks', () {
    test('a task with every field round-trips after a restart', () async {
      final path = _newPath();
      final db = LocalDatabase.open(path);
      await _repo(db)
          .saveProject(const Project(id: 'p1', name: 'Home', position: 0));
      await _repo(db).saveTask(
        Task(
          id: 't1',
          projectId: 'p1',
          title: 'Pay bill',
          status: TaskStatus.inProgress,
          priority: TaskPriority.high,
          dueDate: const CalendarDate(2026, 11, 13),
          notes: 'Line one\nLine two',
          position: 4,
        ),
      );
      db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final task = (await _repo(reopened).loadTasks()).single;

      expect(task.id, 't1');
      expect(task.title, 'Pay bill');
      expect(task.status, TaskStatus.inProgress);
      expect(task.priority, TaskPriority.high);
      expect(task.dueDate?.toIsoString(), '2026-11-13');
      expect(task.notes, 'Line one\nLine two');
      expect(task.position, 4);
    });

    test(
      'the Phase 1 values review, archived and none are preserved',
      () async {
        final db = LocalDatabase.open(_newPath());
        addTearDown(db.close);
        final repo = _repo(db);
        await repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await repo.saveTask(
          makeTask(id: 'r', projectId: 'p1', status: TaskStatus.review),
        );
        await repo.saveTask(
          makeTask(id: 'a', projectId: 'p1', status: TaskStatus.archived),
        );
        await repo.saveTask(
          makeTask(id: 'n', projectId: 'p1', priority: TaskPriority.none),
        );

        final byId = {for (final t in await repo.loadTasks()) t.id: t};

        expect(byId['r']?.status, TaskStatus.review);
        expect(byId['a']?.status, TaskStatus.archived);
        expect(byId['n']?.priority, TaskPriority.none);
      },
    );

    test('empty notes are stored and read back as empty text', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 't1', projectId: 'p1', notes: ''));

      expect((await repo.loadTasks()).single.notes, '');
    });

    test('a date-only due date keeps its day across a restart', () async {
      final path = _newPath();
      final db = LocalDatabase.open(path);
      await _repo(db)
          .saveProject(const Project(id: 'p1', name: 'Home', position: 0));
      await _repo(db).saveTask(
        makeTask(
          id: 't1',
          projectId: 'p1',
          dueDate: const CalendarDate(2028, 2, 29),
        ),
      );
      db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      expect(
        (await _repo(reopened).loadTasks()).single.dueDate?.toIsoString(),
        '2028-02-29',
      );
    });

    test('an edit updates the stored row and advances its version', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 't1', projectId: 'p1', title: 'Old'));

      await repo.saveTask(makeTask(id: 't1', projectId: 'p1', title: 'New'));

      expect((await repo.loadTasks()).single.title, 'New');
      expect(_rows(db, 'tasks', 'id', 't1').single['version'], 2);
    });

    test('repeated save of identical content is idempotent', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      final task = makeTask(id: 't1', projectId: 'p1', title: 'Same');

      await repo.saveTask(task);
      await repo.saveTask(task);
      await repo.saveTask(task);

      expect(_rows(db, 'tasks', 'id', 't1'), hasLength(1));
      expect(_rows(db, 'tasks', 'id', 't1').single['version'], 1);
      // The project insert and the first task insert. Repeats write nothing.
      expect(_outbox(db), hasLength(2));
    });

    test('owner_id is recorded on every task row', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 't1', projectId: 'p1'));

      expect(_rows(db, 'tasks', 'id', 't1').single['owner_id'], _owner);
    });
  });

  group('nested subtasks', () {
    test(
      'a subtask persists and keeps its parent link after restart',
      () async {
        final path = _newPath();
        final db = LocalDatabase.open(path);
        await _repo(db)
            .saveProject(const Project(id: 'p1', name: 'Home', position: 0));
        await _repo(db)
            .saveTask(makeTask(id: 'trip', projectId: 'p1', title: 'Trip'));
        await _repo(db).saveTask(
          makeTask(
            id: 'train',
            projectId: 'p1',
            parentId: 'trip',
            title: 'Train',
          ),
        );
        db.close();

        final reopened = LocalDatabase.open(path);
        addTearDown(reopened.close);
        final byId = {
          for (final t in await _repo(reopened).loadTasks()) t.id: t,
        };

        expect(byId['train']?.parentId, 'trip');
        expect(byId['trip']?.parentId, isNull);
      },
    );

    test('a three-level hierarchy is rebuilt after restart', () async {
      final path = _newPath();
      final db = LocalDatabase.open(path);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 'a', projectId: 'p1'));
      await repo.saveTask(makeTask(id: 'b', projectId: 'p1', parentId: 'a'));
      await repo.saveTask(makeTask(id: 'c', projectId: 'p1', parentId: 'b'));
      db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final byId = {for (final t in await _repo(reopened).loadTasks()) t.id: t};

      expect(byId['c']?.parentId, 'b');
      expect(byId['b']?.parentId, 'a');
      expect(byId['a']?.parentId, isNull);
    });

    test(
      'a parent in another project is refused and nothing is written',
      () async {
        final db = LocalDatabase.open(_newPath());
        addTearDown(db.close);
        final repo = _repo(db);
        await repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await repo.saveProject(
          const Project(id: 'p2', name: 'Work', position: 1),
        );
        await repo.saveTask(makeTask(id: 'a', projectId: 'p1'));

        await expectLater(
          repo.saveTask(makeTask(id: 'x', projectId: 'p2', parentId: 'a')),
          throwsA(isA<RepositoryException>()),
        );
        expect(_rows(db, 'tasks', 'id', 'x'), isEmpty);
      },
    );
  });

  group('soft deletion', () {
    test(
      'a soft-deleted task is hidden from loads but kept in the file',
      () async {
        final db = LocalDatabase.open(_newPath());
        addTearDown(db.close);
        final repo = _repo(db);
        await repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        await repo.saveTask(makeTask(id: 't1', projectId: 'p1'));

        await repo.softDeleteTask('t1');

        expect(await repo.loadTasks(), isEmpty);
        final row = _rows(db, 'tasks', 'id', 't1').single;
        expect(row['deleted_at'], isNotNull);
        expect(row['version'], 2);
      },
    );

    test('deleting an unknown task is reported as an error', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);

      await expectLater(
        _repo(db).softDeleteTask('missing'),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('failed writes', () {
    test(
      'a title over the stored limit fails with no partial row or outbox entry',
      () async {
        final db = LocalDatabase.open(_newPath());
        addTearDown(db.close);
        final repo = _repo(db);
        await repo.saveProject(
          const Project(id: 'p1', name: 'Home', position: 0),
        );
        final outboxBefore = _outbox(db).length;

        await expectLater(
          repo.saveTask(makeTask(id: 'big', projectId: 'p1', title: 'x' * 501)),
          throwsA(isA<RepositoryException>()),
        );

        expect(_rows(db, 'tasks', 'id', 'big'), isEmpty);
        expect(_outbox(db).length, outboxBefore);
      },
    );

    test('the database stays usable after a failed write', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await expectLater(
        repo.saveTask(makeTask(id: 'big', projectId: 'p1', title: 'x' * 501)),
        throwsA(isA<RepositoryException>()),
      );

      await repo.saveTask(makeTask(id: 'ok', projectId: 'p1', title: 'Fine'));

      expect((await repo.loadTasks()).single.title, 'Fine');
    });
  });

  group('outbox', () {
    test('each committed change writes one outbox operation with a stable identity', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 't1', projectId: 'p1', title: 'A'));
      await repo.saveTask(makeTask(id: 't1', projectId: 'p1', title: 'B'));

      final rows = _outbox(db);
      expect(rows, hasLength(3));
      final operationIds = rows.map((row) => row['operation_id']).toSet();
      expect(operationIds, hasLength(3));
      final update = rows.last;
      expect(update['entity_id'], 't1');
      expect(update['base_version'], 1);
      expect(update['state'], 'pending');
      expect(update['created_at_utc'], '2026-11-12T10:00:00.000Z');
    });
  });

  group('restart', () {
    test('a full close and reopen returns the same workspace', () async {
      final path = _newPath();
      final db = LocalDatabase.open(path);
      final repo = _repo(db);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 'a', projectId: 'p1', title: 'Alpha'));
      await repo.saveTask(
        makeTask(id: 'b', projectId: 'p1', parentId: 'a', title: 'Beta'),
      );
      db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final tasks = await _repo(reopened).loadTasks();

      final ids = tasks.map((t) => t.id).toList()..sort();
      expect(ids, ['a', 'b']);
      expect(tasks.firstWhere((t) => t.id == 'b').parentId, 'a');
    });
  });
}
