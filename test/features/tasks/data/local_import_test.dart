import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_import.dart';
import 'package:nexora/features/tasks/data/snapshot_digest.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/sequential_id_generator.dart';
import '../../../support/task_fixtures.dart';

/// The manual local-to-account import: preview first, one transaction, a verified
/// backup before the write, no data lost and no silent changes.
late Directory _dir;

String _file(String name) => '${_dir.path}${Platform.pathSeparator}$name';

SequentialIdGenerator _ids([String prefix = 'x']) =>
    SequentialIdGenerator([for (var i = 0; i < 2000; i++) '$prefix-$i']);

Future<SqliteTaskRepository> _seedLocal(LocalDatabase db) async {
  final repo = SqliteTaskRepository(db, ownerId: 'local-owner', ids: _ids('l'));
  await repo.saveProject(const Project(id: 'lp1', name: 'Work', position: 0));
  await repo.saveProject(const Project(id: 'lp2', name: 'Home', position: 1));
  await repo.saveTask(
    makeTask(
      id: 'lt1',
      projectId: 'lp1',
      title: 'Plan',
      notes: 'multi\nline notes',
      priority: TaskPriority.high,
      dueDate: CalendarDate(2026, 12, 24),
      position: 0,
    ),
  );
  await repo.saveTask(
    makeTask(
      id: 'lt2',
      projectId: 'lp1',
      parentId: 'lt1',
      title: 'Step one',
      status: TaskStatus.done,
      position: 0,
    ),
  );
  await repo.saveTask(
    makeTask(
      id: 'lt3',
      projectId: 'lp1',
      parentId: 'lt2',
      title: 'Detail',
      position: 0,
    ),
  );
  await repo.saveTask(
    makeTask(id: 'lt4', projectId: 'lp2', title: 'Buy milk', position: 0),
  );
  return repo;
}

void main() {
  late LocalDatabase local;
  late LocalDatabase account;
  late SqliteTaskRepository accountRepo;
  late String localPath;

  LocalImportService service({void Function()? beforeCommit}) {
    return LocalImportService(
      sourcePath: localPath,
      target: account,
      repository: accountRepo,
      ids: _ids('n'),
      beforeCommit: beforeCommit,
    );
  }

  setUp(() async {
    _dir = Directory.systemTemp.createTempSync('nexora-import-test-');
    localPath = _file('nexora.db');
    local = LocalDatabase.open(localPath);
    await _seedLocal(local);
    local.close();
    Directory('${_dir.path}${Platform.pathSeparator}acc').createSync();
    account = LocalDatabase.open(_file('acc${Platform.pathSeparator}nexora.db'));
    accountRepo = SqliteTaskRepository(
      account,
      ownerId: 'account-owner',
      ids: _ids('a'),
    );
  });

  tearDown(() {
    try {
      account.close();
    } on Object {
      // already closed
    }
    _dir.deleteSync(recursive: true);
  });

  String sourceDigest() {
    final db = LocalDatabase.open(localPath);
    try {
      return snapshotDigest(db.raw);
    } finally {
      db.close();
    }
  }

  test('preview offers the live synchronized projects and writes nothing', () async {
    final before = snapshotDigest(account.raw);
    final sourceBefore = sourceDigest();
    final preview = await service().preview();
    expect(preview.candidates.map((c) => c.project.name), ['Work', 'Home']);
    expect(preview.candidates.first.tasks, hasLength(3));
    expect(preview.isEmpty, isFalse);
    expect(snapshotDigest(account.raw), before);
    expect(sourceDigest(), sourceBefore);
  });

  test('import copies projects and tasks with new ids, hierarchy and notes', () async {
    final sourceBefore = sourceDigest();
    final result = await service().run([
      const ImportChoice(sourceProjectId: 'lp1'),
    ]);
    expect(result.projectsCreated, 1);
    expect(result.tasksImported, 3);
    expect(File(result.backupFile).existsSync(), isTrue);

    final projects = await accountRepo.loadProjects();
    expect(projects.map((p) => p.name), ['Work']);
    expect(projects.single.id, isNot('lp1'));
    final tasks = await accountRepo.loadTasks();
    final plan = tasks.singleWhere((t) => t.title == 'Plan');
    final step = tasks.singleWhere((t) => t.title == 'Step one');
    final detail = tasks.singleWhere((t) => t.title == 'Detail');
    expect(plan.notes, 'multi\nline notes');
    expect(plan.priority, TaskPriority.high);
    expect(plan.dueDate, CalendarDate(2026, 12, 24));
    expect(step.parentId, plan.id);
    expect(detail.parentId, step.id);
    expect(step.status, TaskStatus.done);
    expect({plan.id, step.id, detail.id}.intersection({'lt1', 'lt2', 'lt3'}), isEmpty);
    // The other project was not chosen, so it is not imported.
    expect(tasks.where((t) => t.title == 'Buy milk'), isEmpty);
    // The source is unchanged, byte for byte in content.
    expect(sourceDigest(), sourceBefore);
  });

  test('imported records are queued for synchronization, nothing else is', () async {
    await service().run([const ImportChoice(sourceProjectId: 'lp1')]);
    expect(SyncStateStore(account).counts().pending, 4); // 1 project + 3 tasks
  });

  test('the backup holds the pre-import state', () async {
    await accountRepo.saveProject(
      const Project(id: 'existing', name: 'Existing', position: 0),
    );
    final before = snapshotDigest(account.raw);
    final result = await service().run([
      const ImportChoice(sourceProjectId: 'lp2'),
    ]);
    final copy = LocalDatabase.open(result.backupFile);
    try {
      expect(snapshotDigest(copy.raw), before);
    } finally {
      copy.close();
    }
    expect(snapshotDigest(account.raw), isNot(before));
  });

  test('a failure inside the transaction rolls everything back and keeps the backup', () async {
    final before = snapshotDigest(account.raw);
    Object? error;
    try {
      await service(beforeCommit: () => throw StateError('boom')).run([
        const ImportChoice(sourceProjectId: 'lp1'),
      ]);
    } on ImportException catch (e) {
      error = e;
    }
    expect((error as ImportException).code, 'write_failed');
    expect(snapshotDigest(account.raw), before);
    expect(await accountRepo.loadProjects(), isEmpty);
    final backups = Directory('${_dir.path}${Platform.pathSeparator}acc')
        .listSync()
        .where((f) => f.path.contains('.pre-import-'));
    expect(backups, isNotEmpty);
  });

  test('importing the same project again is blocked unless confirmed', () async {
    await service().run([const ImportChoice(sourceProjectId: 'lp1')]);
    final preview = await service().preview();
    final work = preview.candidates.firstWhere((c) => c.project.id == 'lp1');
    expect(work.warnings, contains(ImportWarning.alreadyImported));
    Object? error;
    try {
      await service().run([const ImportChoice(sourceProjectId: 'lp1')]);
    } on ImportException catch (e) {
      error = e;
    }
    expect((error as ImportException).code, 'blocked_duplicate');
    expect(await accountRepo.loadProjects(), hasLength(1));
  });

  test('merging into an existing project skips tasks that already exist', () async {
    await service().run([const ImportChoice(sourceProjectId: 'lp1')]);
    final destination = (await accountRepo.loadProjects()).single.id;
    final result = await service().run([
      ChoiceFor.merge('lp1', destination),
    ]);
    expect(result.projectsCreated, 0);
    expect(result.tasksImported, 0);
    expect(result.tasksSkippedDuplicate, 3);
    expect(await accountRepo.loadTasks(), hasLength(3));
  });

  test('same-name project is warned about, not merged automatically', () async {
    await accountRepo.saveProject(
      const Project(id: 'w', name: 'work', position: 0),
    );
    final preview = await service().preview();
    final work = preview.candidates.firstWhere((c) => c.project.id == 'lp1');
    expect(work.warnings, contains(ImportWarning.sameNameExists));
    await service().run([const ImportChoice(sourceProjectId: 'lp1')]);
    expect(await accountRepo.loadProjects(), hasLength(2));
  });

  test('unknown source, nothing selected and a missing source are refused', () async {
    for (final entry in {
      'unknown_source': () => service().run([
        const ImportChoice(sourceProjectId: 'nope'),
      ]),
      'nothing_selected': () => service().run([]),
    }.entries) {
      Object? error;
      try {
        await entry.value();
      } on ImportException catch (e) {
        error = e;
      }
      expect((error as ImportException).code, entry.key);
    }
    File(localPath).deleteSync();
    Object? error;
    try {
      await service().preview();
    } on ImportException catch (e) {
      error = e;
    }
    expect((error as ImportException).code, 'no_source');
    expect(await accountRepo.loadProjects(), isEmpty);
  });

  test('local-only and unclassified records are never offered', () async {
    final db = LocalDatabase.open(localPath);
    db.raw.execute("UPDATE projects SET sync_scope = 'local_only' WHERE id = 'lp2'");
    db.raw.execute("UPDATE tasks SET sync_scope = 'unclassified' WHERE id = 'lt3'");
    db.close();
    final preview = await service().preview();
    expect(preview.candidates.map((c) => c.project.id), ['lp1']);
    expect(preview.candidates.single.tasks.map((t) => t.id), ['lt1', 'lt2']);
    expect(preview.skipped.localOnly, greaterThan(0));
    expect(preview.skipped.unclassified, greaterThan(0));
  });

  test('pending work already in the account is untouched', () async {
    await accountRepo.saveProject(
      const Project(id: 'mine', name: 'Mine', position: 0),
    );
    await accountRepo.saveTask(
      makeTask(id: 'mt', projectId: 'mine', title: 'Mine task'),
    );
    final pendingBefore = SyncStateStore(account).counts().pending;
    await service().run([const ImportChoice(sourceProjectId: 'lp2')]);
    expect(
      SyncStateStore(account).counts().pending,
      pendingBefore + 2, // new project + one task
    );
    final tasks = await accountRepo.loadTasks();
    expect(tasks.any((t) => t.id == 'mt' && t.title == 'Mine task'), isTrue);
  });
}

/// A merge choice (kept out of the const constructor call sites for readability).
final class ChoiceFor {
  static ImportChoice merge(String source, String destination) => ImportChoice(
    sourceProjectId: source,
    destinationProjectId: destination,
    allowDuplicate: true,
  );
}
