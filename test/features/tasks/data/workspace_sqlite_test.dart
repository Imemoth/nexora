import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/application/workspace_transition.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_storage.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/fixed_clock.dart';
import '../../../support/result_matchers.dart';
import '../../../support/sequential_id_generator.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart' show testToday;

/// The workspace over a real SQLite file: a Save that the user saw is the value a
/// restart returns, a Discard writes nothing, and a failed Save keeps the draft.
late Directory _dir;
var _n = 0;

String _path() {
  _n++;
  return '${_dir.path}${Platform.pathSeparator}w-$_n.db';
}

SqliteTaskRepository _repo(LocalDatabase db, IdGenerator ids) {
  return SqliteTaskRepository(db, ownerId: 'owner-local', ids: ids);
}

TaskWorkspace _workspace(SqliteTaskRepository repo, IdGenerator ids) {
  return TaskWorkspace(
    repository: repo,
    clock: const FixedClock(testToday),
    ids: ids,
  );
}

/// Enough ids for every outbox entry a test writes.
SequentialIdGenerator _ids() {
  return SequentialIdGenerator([for (var i = 0; i < 500; i++) 'id-$i']);
}

int _count(LocalDatabase db, String table) {
  return db.raw.select('SELECT COUNT(*) AS n FROM $table').single['n'] as int;
}

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('nexora-ws-test-');
  });

  tearDown(() {
    _dir.deleteSync(recursive: true);
  });

  test('Save writes the edit to the file, and a restart shows it', () async {
    final path = _path();
    final db = LocalDatabase.open(path);
    final ids = _ids();
    final repo = _repo(db, ids);
    await repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
    await repo.saveTask(makeTask(id: 'a', projectId: 'p1', title: 'Alpha'));
    final ws = _workspace(repo, ids);
    await ws.load();

    ws.requestSelectTask('a');
    ws.editDraft(title: 'Alpha 2', status: TaskStatus.inProgress);
    okValue(await ws.saveDraft());
    db.close();

    final reopened = LocalDatabase.open(path);
    addTearDown(reopened.close);
    final restartIds = _ids();
    final restarted = _workspace(_repo(reopened, restartIds), restartIds);
    await restarted.load();

    expect(restarted.state.tasks['a']?.title, 'Alpha 2');
    expect(restarted.state.tasks['a']?.status, TaskStatus.inProgress);
  });

  test('Discard writes nothing to the file', () async {
    final db = LocalDatabase.open(_path());
    addTearDown(db.close);
    final ids = _ids();
    final repo = _repo(db, ids);
    await repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
    await repo.saveTask(makeTask(id: 'a', projectId: 'p1', title: 'Alpha'));
    await repo.saveTask(makeTask(id: 'b', projectId: 'p1', title: 'Beta'));
    final outboxBefore = _count(db, 'sync_outbox');
    final ws = _workspace(repo, ids);
    await ws.load();

    ws.requestSelectTask('a');
    ws.editDraft(title: 'Edited, then discarded');
    ws.requestSelectTask('b');
    await ws.resolvePending(PendingResolution.discard);

    expect(_count(db, 'sync_outbox'), outboxBefore);
    expect(
      db.raw.select("SELECT title FROM tasks WHERE id = 'a'").single['title'],
      'Alpha',
    );
  });

  test(
    'a failed Save keeps the draft, and the file keeps the saved value',
    () async {
      final db = LocalDatabase.open(_path());
      addTearDown(db.close);
      final ids = _ids();
      final repo = _repo(db, ids);
      await repo.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await repo.saveTask(makeTask(id: 'a', projectId: 'p1', title: 'Alpha'));
      final ws = _workspace(repo, ids);
      await ws.load();
      // Simulate a disk-level write failure: the database rejects any task update.
      db.raw.execute(
        "CREATE TRIGGER refuse_update BEFORE UPDATE ON tasks "
        "BEGIN SELECT RAISE(ABORT, 'simulated write failure'); END;",
      );

      ws.requestSelectTask('a');
      ws.editDraft(title: 'Changed');
      final result = await ws.saveDraft();

      expect(errValue(result), WorkspaceError.saveFailed);
      expect(ws.state.error, WorkspaceError.saveFailed);
      expect(ws.state.draft?.title, 'Changed');
      expect(ws.state.draft?.isDirty, isTrue);
      expect(
        db.raw.select("SELECT title FROM tasks WHERE id = 'a'").single['title'],
        'Alpha',
      );
    },
  );

  group('startup', () {
    test('an existing database is never overwritten by demo data', () async {
      final path = _path();
      final db = LocalDatabase.open(path);
      final ids = _ids();
      final repo = _repo(db, ids);
      await repo.saveProject(
        const Project(id: 'mine', name: 'Mine', position: 0),
      );
      await repo.saveTask(
        makeTask(id: 'mine-1', projectId: 'mine', title: 'Mine'),
      );
      final demo = buildDemoData(testToday);

      final seeded = await repo.seedDemoData(
        projects: demo.projects,
        tasks: demo.tasks,
      );
      db.close();

      expect(seeded, isFalse);
      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final ids2 = (await _repo(
        reopened,
        ids,
      ).loadTasks()).map((t) => t.id).toList();
      expect(ids2, ['mine-1']);
    });

    test(
      'demo data is written once into a new database and not again',
      () async {
        final db = LocalDatabase.open(_path());
        addTearDown(db.close);
        final repo = _repo(db, _ids());
        final demo = buildDemoData(testToday);

        expect(
          await repo.seedDemoData(projects: demo.projects, tasks: demo.tasks),
          isTrue,
        );
        expect(
          await repo.seedDemoData(projects: demo.projects, tasks: demo.tasks),
          isFalse,
        );

        expect((await repo.loadTasks()).length, demo.tasks.length);
        // Seeded rows are local and add no outbox entries, so they never sync.
        expect(_count(db, 'sync_outbox'), 0);
      },
    );

    test(
      'the default project is created once, for an empty workspace',
      () async {
        final db = LocalDatabase.open(_path());
        addTearDown(db.close);
        final repo = _repo(db, _ids());

        final created = await repo.ensureDefaultProject('Inbox');
        final again = await repo.ensureDefaultProject('Inbox');

        expect(created?.name, 'Inbox');
        expect(again, isNull);
        expect(await repo.loadProjects(), hasLength(1));
      },
    );

    test('the owner id is created once and reused on every launch', () {
      final path = _path();
      final db = LocalDatabase.open(path);
      final first = ownerIdOf(db, SequentialIdGenerator(['owner-1']));
      db.close();

      final reopened = LocalDatabase.open(path);
      addTearDown(reopened.close);
      final second = ownerIdOf(reopened, SequentialIdGenerator(['owner-2']));

      expect(first, 'owner-1');
      expect(second, 'owner-1');
    });

    test(
      'the database location is the approved one, with an override for tests',
      () {
        expect(
          localDatabasePath({'LOCALAPPDATA': r'C:\Users\me\AppData\Local'}),
          r'C:\Users\me\AppData\Local\Nexora\nexora.db',
        );
        expect(
          localDatabasePath({
            'NEXORA_DB_PATH': r'D:\test\n.db',
            'LOCALAPPDATA': r'C:\x',
          }),
          r'D:\test\n.db',
        );
      },
    );
  });
}
