import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/sqlite_settings_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import '../../../support/task_fixtures.dart';

const _owner = 'owner-local';

late Directory _dir;
var _counter = 0;

String _newPath() {
  _counter++;
  return '${_dir.path}${Platform.pathSeparator}del-$_counter.db';
}

SqliteTaskRepository _repo(LocalDatabase db) {
  return SqliteTaskRepository(
    db,
    ownerId: _owner,
    now: () => DateTime.utc(2026, 11, 14, 10),
  );
}

List<Map<String, Object?>> _outbox(LocalDatabase db) {
  return db.raw
      .select('SELECT * FROM sync_outbox ORDER BY rowid')
      .map((row) => {for (final key in row.keys) key: row[key]})
      .toList();
}

Future<SqliteTaskRepository> _seeded(LocalDatabase db) async {
  final repo = _repo(db);
  await repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
  await repo.saveProject(const Project(id: 'p2', name: 'Work', position: 1));
  await repo.saveTask(makeTask(id: 'root', projectId: 'p1'));
  await repo.saveTask(makeTask(id: 'kid', projectId: 'p1', parentId: 'root'));
  await repo.saveTask(makeTask(id: 'other', projectId: 'p2'));
  return repo;
}

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('nexora-delete-test-');
  });

  tearDown(() {
    _dir.deleteSync(recursive: true);
  });

  group('deleteTasks', () {
    test('tombstones every task and queues deletes leaf-first', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);
      final before = _outbox(db).length;

      await repo.deleteTasks(['kid', 'root']);

      final live = await repo.loadTasks();
      expect(live.map((t) => t.id), ['other']);
      final added = _outbox(db).skip(before).toList();
      expect(added.map((o) => o['operation_type']), ['delete', 'delete']);
      expect(added.map((o) => o['entity_id']), ['kid', 'root']);
    });

    test('is all or nothing when one id is unknown', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);
      final before = _outbox(db).length;

      await expectLater(
        repo.deleteTasks(['kid', 'missing']),
        throwsA(isA<RepositoryException>()),
      );

      expect((await repo.loadTasks()).length, 3);
      expect(_outbox(db).length, before);
    });
  });

  group('deleteProject', () {
    test('tombstones the tasks leaf-first, then the project', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);
      final before = _outbox(db).length;

      await repo.deleteProject('p1', ['kid', 'root']);

      expect((await repo.loadProjects()).map((p) => p.id), ['p2']);
      expect((await repo.loadTasks()).map((t) => t.id), ['other']);
      final added = _outbox(db).skip(before).toList();
      expect(added.map((o) => o['entity_id']), ['kid', 'root', 'p1']);
      expect(added.last['entity_type'], 'project');
      expect(added.last['operation_type'], 'delete');
    });

    test(
      'refuses when a live task is not listed, and changes nothing',
      () async {
        final db = LocalDatabase.open(_newPath());
        addTearDown(db.close);
        final repo = await _seeded(db);
        final before = _outbox(db).length;

        await expectLater(
          repo.deleteProject('p1', ['root']),
          throwsA(isA<RepositoryException>()),
        );

        expect((await repo.loadProjects()).length, 2);
        expect((await repo.loadTasks()).length, 3);
        expect(_outbox(db).length, before);
      },
    );

    test('an unknown project is an error', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);

      await expectLater(
        repo.deleteProject('nope', const []),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('settings store', () {
    test('defaults to System', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);

      expect(
        await SqliteSettingsStore(db).loadThemePreference(),
        ThemePreference.system,
      );
    });

    test('keeps the saved preference across a reopen', () async {
      final path = _newPath();
      final first = LocalDatabase.open(path);
      await SqliteSettingsStore(first)
          .saveThemePreference(ThemePreference.light);
      first.close();

      final second = LocalDatabase.open(path);
      addTearDown(second.close);

      expect(
        await SqliteSettingsStore(second).loadThemePreference(),
        ThemePreference.light,
      );
    });

    test('writes no outbox entry', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);

      await SqliteSettingsStore(db).saveThemePreference(ThemePreference.dark);

      expect(_outbox(db), isEmpty);
    });
  });
}
