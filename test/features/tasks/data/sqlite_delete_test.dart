import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import '../../../support/task_fixtures.dart';

/// The workspace deletes through `TaskRepository.deleteTaskTree` and
/// `deleteProjectTree`. These tests check that the SQLite repository answers
/// them with its atomic tree delete. The outbox shape of a synchronized tree
/// delete is covered by the sync engine and two-device tests.
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

Future<SqliteTaskRepository> _seeded(LocalDatabase db) async {
  final repo = _repo(db);
  await repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
  await repo.saveProject(const Project(id: 'p2', name: 'Work', position: 1));
  await repo.saveTask(makeTask(id: 'root', projectId: 'p1'));
  await repo.saveTask(makeTask(id: 'kid', projectId: 'p1', parentId: 'root'));
  await repo.saveTask(makeTask(id: 'grand', projectId: 'p1', parentId: 'kid'));
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

  group('deleteTaskTree', () {
    test('removes the task and every descendant, and nothing else', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);

      await repo.deleteTaskTree('root');

      expect((await repo.loadTasks()).map((t) => t.id), ['other']);
      expect((await repo.loadProjects()).length, 2);
    });

    test('keeps rows as tombstones, not hard deletes', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);

      await repo.deleteTaskTree('root');

      final rows = db.raw.select(
        "SELECT id, deleted_at FROM tasks WHERE id IN ('root', 'kid', 'grand')",
      );
      expect(rows.length, 3);
      for (final row in rows) {
        expect(row['deleted_at'], isNotNull);
      }
    });

    test('an unknown or already deleted task is an error', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);

      await expectLater(
        repo.deleteTaskTree('missing'),
        throwsA(isA<RepositoryException>()),
      );
      await repo.deleteTaskTree('root');
      await expectLater(
        repo.deleteTaskTree('root'),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('deleteProjectTree', () {
    test(
      'removes the project and all its tasks, leaving other projects',
      () async {
        final db = LocalDatabase.open(_newPath());
        addTearDown(db.close);
        final repo = await _seeded(db);

        await repo.deleteProjectTree('p1');

        expect((await repo.loadProjects()).map((p) => p.id), ['p2']);
        expect((await repo.loadTasks()).map((t) => t.id), ['other']);
      },
    );

    test('an unknown project is an error and changes nothing', () async {
      final db = LocalDatabase.open(_newPath());
      addTearDown(db.close);
      final repo = await _seeded(db);

      await expectLater(
        repo.deleteProjectTree('nope'),
        throwsA(isA<RepositoryException>()),
      );

      expect((await repo.loadProjects()).length, 2);
      expect((await repo.loadTasks()).length, 4);
    });
  });
}
