import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/application/workspace_error.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/domain/project.dart';

import '../../../support/fixed_clock.dart';
import '../../../support/sequential_id_generator.dart';
import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart' show testToday;

/// The Phase 5 delete flow over a real SQLite file: one transaction, soft
/// delete (tombstones), and, for synchronized rows, ONE delete operation that
/// lists the whole subtree (applied by the server completely or not at all).
void main() {
  late Directory dir;
  late LocalDatabase db;
  late SqliteTaskRepository repo;
  late TaskWorkspace ws;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('nexora-del-test-');
    db = LocalDatabase.open('${dir.path}${Platform.pathSeparator}d.db');
    final ids = SequentialIdGenerator([for (var i = 0; i < 500; i++) 'id-$i']);
    repo = SqliteTaskRepository(db, ownerId: 'owner', ids: ids);
    await repo.saveProject(const Project(id: 'p1', name: 'Home', position: 0));
    await repo.saveProject(const Project(id: 'p2', name: 'Work', position: 1));
    await repo.saveTask(makeTask(id: 'root', title: 'Root'));
    await repo.saveTask(makeTask(id: 'kid', parentId: 'root', title: 'Kid'));
    await repo.saveTask(
      makeTask(id: 'grandkid', parentId: 'kid', title: 'Grandkid'),
    );
    await repo.saveTask(makeTask(id: 'keep', title: 'Keep'));
    ws = TaskWorkspace(
      repository: repo,
      clock: const FixedClock(testToday),
      ids: ids,
    );
    await ws.load();
  });

  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  int liveTasks() =>
      db.raw
              .select(
                'SELECT COUNT(*) AS n FROM tasks WHERE deleted_at IS NULL',
              )
              .single['n']
          as int;

  test(
    'deleting a task tombstones the whole subtree in one transaction',
    () async {
      final result = await ws.deleteTask('root');
      expect(result, isA<Ok<List<String>, WorkspaceError>>());
      expect(liveTasks(), 1);
      expect(ws.state.tasks.keys, ['keep']);
      // Soft delete: the rows stay as tombstones.
      final tombstones = db.raw
          .select('SELECT id FROM tasks WHERE deleted_at IS NOT NULL')
          .map((r) => r['id'])
          .toSet();
      expect(tombstones, {'root', 'kid', 'grandkid'});
    },
  );

  test(
    'a synchronized subtree queues one delete operation listing every task',
    () async {
      await ws.deleteTask('root');
      final deletes = db.raw.select(
        "SELECT entity_id, payload_json FROM sync_outbox WHERE op_type = 'delete'",
      );
      // One operation for the root, none for its descendants.
      expect(deletes, hasLength(1));
      expect(deletes.single['entity_id'], 'root');
      final payload = jsonDecode(
        deletes.single['payload_json'] as String,
      ) as Map<String, Object?>;
      final listed = [
        for (final entry in payload['tree']! as List)
          if (entry is String) entry else (entry as Map)['id'] as String,
      ];
      expect(listed.toSet(), {'kid', 'grandkid'});
    },
  );

  test('deleting a project tombstones it and all its tasks', () async {
    await repo.saveTask(
      makeTask(id: 'w1', projectId: 'p2', title: 'Work task'),
    );
    await ws.refresh();
    final result = await ws.deleteProject('p2');
    expect(result, isA<Ok<List<String>, WorkspaceError>>());
    final project = db.raw
        .select("SELECT deleted_at FROM projects WHERE id = 'p2'")
        .single;
    expect(project['deleted_at'], isNotNull);
    final task = db.raw
        .select("SELECT deleted_at FROM tasks WHERE id = 'w1'")
        .single;
    expect(task['deleted_at'], isNotNull);
    expect(ws.state.projects.map((p) => p.id), ['p1']);
  });

  test('a failed delete changes nothing', () async {
    // Unknown id: the repository refuses and nothing is written.
    final before = liveTasks();
    final result = await ws.deleteTask('missing');
    expect(result, isA<Err<List<String>, WorkspaceError>>());
    expect(liveTasks(), before);
  });
}
