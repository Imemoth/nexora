import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import '../../../support/task_fixtures.dart';

/// S5-0 failure injection (CR-2A-001 REQ-5 `domain_write_and_outbox_row_atomic`).
/// A SQLite trigger aborts one half of a domain write plus outbox insert; the
/// whole write must roll back, so a domain row never exists without its
/// outbox row and the reverse.
void main() {
  late Directory dir;
  var counter = 0;

  setUp(() => dir = Directory.systemTemp.createTempSync('nexora-inject-'));
  tearDown(() => dir.deleteSync(recursive: true));

  LocalDatabase open() {
    counter++;
    final db = LocalDatabase.open('${dir.path}/f$counter.db');
    addTearDown(db.close);
    return db;
  }

  SqliteTaskRepository repo(LocalDatabase db) => SqliteTaskRepository(
    db,
    ownerId: 'owner-local',
    now: () => DateTime.utc(2026, 11, 12, 10),
  );

  int count(LocalDatabase db, String table) =>
      db.raw.select('SELECT COUNT(*) AS n FROM $table').single['n'] as int;

  Future<void> seedProject(LocalDatabase db) =>
      repo(db).saveProject(const Project(id: 'p1', name: 'Seed', position: 0));

  test('a failing outbox insert rolls the task write back', () async {
    final db = open();
    await seedProject(db);
    final tasksBefore = count(db, 'tasks');
    final outboxBefore = count(db, 'sync_outbox');
    db.raw.execute(
      "CREATE TRIGGER inject_outbox_failure BEFORE INSERT ON sync_outbox "
      "BEGIN SELECT RAISE(ABORT, 'injected outbox failure'); END",
    );

    await expectLater(
      repo(db).saveTask(makeTask(id: 't1')),
      throwsA(isA<RepositoryException>()),
    );

    expect(count(db, 'tasks'), tasksBefore);
    expect(count(db, 'sync_outbox'), outboxBefore);
    expect(db.raw.autocommit, isTrue, reason: 'no transaction left open');
  });

  test('a failing domain write leaves no outbox row', () async {
    final db = open();
    await seedProject(db);
    final tasksBefore = count(db, 'tasks');
    final outboxBefore = count(db, 'sync_outbox');
    db.raw.execute(
      "CREATE TRIGGER inject_task_failure BEFORE INSERT ON tasks "
      "BEGIN SELECT RAISE(ABORT, 'injected task failure'); END",
    );

    await expectLater(
      repo(db).saveTask(makeTask(id: 't1')),
      throwsA(isA<RepositoryException>()),
    );

    expect(count(db, 'tasks'), tasksBefore);
    expect(count(db, 'sync_outbox'), outboxBefore);
    expect(db.raw.autocommit, isTrue);
  });

  test('a failing outbox insert rolls an edit and a delete back', () async {
    final db = open();
    await seedProject(db);
    await repo(db).saveTask(makeTask(id: 't1', title: 'Original'));
    final outboxBefore = count(db, 'sync_outbox');
    db.raw.execute(
      "CREATE TRIGGER inject_outbox_failure BEFORE INSERT ON sync_outbox "
      "BEGIN SELECT RAISE(ABORT, 'injected outbox failure'); END",
    );
    // An edit of a pending create folds into it with an UPDATE of the operation.
    db.raw.execute(
      "CREATE TRIGGER inject_outbox_update_failure BEFORE UPDATE ON sync_outbox "
      "BEGIN SELECT RAISE(ABORT, 'injected outbox update failure'); END",
    );

    await expectLater(
      repo(db).saveTask(makeTask(id: 't1', title: 'Edited')),
      throwsA(isA<RepositoryException>()),
    );
    await expectLater(
      repo(db).softDeleteTask('t1'),
      throwsA(isA<RepositoryException>()),
    );

    final row = db.raw
        .select("SELECT title, deleted_at FROM tasks WHERE id = 't1'")
        .single;
    expect(row['title'], 'Original');
    expect(row['deleted_at'], isNull);
    expect(count(db, 'sync_outbox'), outboxBefore);
  });

  test(
    'the repository works again once the injected failure is removed',
    () async {
      final db = open();
      await seedProject(db);
      db.raw.execute(
        "CREATE TRIGGER inject_outbox_failure BEFORE INSERT ON sync_outbox "
        "BEGIN SELECT RAISE(ABORT, 'injected outbox failure'); END",
      );
      await expectLater(
        repo(db).saveTask(makeTask(id: 't1')),
        throwsA(isA<RepositoryException>()),
      );
      db.raw.execute('DROP TRIGGER inject_outbox_failure');

      await repo(db).saveTask(makeTask(id: 't1'));

      expect(count(db, 'tasks'), 1);
      expect(count(db, 'sync_outbox'), 2); // project create + task create
    },
  );
}
