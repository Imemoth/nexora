import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/snapshot_digest.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/v1_database.dart';

/// S5: migration v1 to v2 on synthetic databases only.
late Directory _dir;
var _n = 0;

String _path() {
  _n++;
  return '${_dir.path}${Platform.pathSeparator}m-$_n.db';
}

List<Map<String, Object?>> _all(Database db, String sql) {
  return [
    for (final row in db.select(sql)) {for (final k in row.keys) k: row[k]},
  ];
}

List<File> _backups(String path) {
  final name = File(path).uri.pathSegments.last;
  return [
    for (final entity in _dir.listSync())
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('$name.pre-v2.') &&
          entity.path.endsWith('.bak'))
        entity,
  ];
}

String _digestOf(String path) {
  final raw = sqlite3.open(path);
  try {
    return snapshotDigest(raw);
  } finally {
    raw.close();
  }
}

Object? _scalar(Database db, String sql) => db.select(sql).first.values.first;

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('nexora-mig-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('classification', () {
    test('a clean pending-create workspace becomes class S with version 0', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      final tasks = _all(
        db.raw,
        'SELECT id, version, sync_scope FROM tasks ORDER BY id',
      );
      expect(tasks.map((r) => r['version']), [0, 0]);
      expect(tasks.map((r) => r['sync_scope']), ['synced', 'synced']);
      final project = _all(
        db.raw,
        'SELECT version, sync_scope FROM projects',
      ).single;
      expect(project['version'], 0);
      expect(project['sync_scope'], 'synced');
      final ops = _all(db.raw, 'SELECT * FROM sync_outbox ORDER BY seq');
      expect(ops.map((r) => r['operation_id']), ['op-p1', 'op-t1', 'op-t2']);
      expect(ops.every((r) => r['op_type'] == 'create'), isTrue);
      expect(ops.every((r) => r['state'] == 'pending'), isTrue);
      expect(ops.every((r) => r['base_version'] == null), isTrue);
      // t1 waits for p1's create; t2 (a subtask) waits for t1's create.
      expect(ops[0]['depends_on_seq'], isNull);
      expect(ops[1]['depends_on_seq'], ops[0]['seq']);
      expect(ops[2]['depends_on_seq'], ops[1]['seq']);
      expect(db.migrationReport!.counts['class_s_entities'], 3);
      expect(db.migrationReport!.counts['class_u_entities'], 0);
    });

    test(
      'later pending upserts are folded into the first create and archived',
      () {
        final path = _path();
        createV1File(path, [
          "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
          v1Project('p1'),
          v1Task('t1', 'p1', title: 'Final title'),
          v1Op('op-p1', 'project', 'p1', v1ProjectPayload('p1')),
          v1Op(
            'op-t1a',
            'task',
            't1',
            v1TaskPayload('t1', 'p1', title: 'First'),
          ),
          v1Op(
            'op-t1b',
            'task',
            't1',
            v1TaskPayload('t1', 'p1', title: 'Final title'),
          ),
        ]);

        final db = LocalDatabase.open(path);
        addTearDown(db.close);

        final live = _all(
          db.raw,
          "SELECT * FROM sync_outbox WHERE entity_id = 't1'",
        ).single;
        expect(live['operation_id'], 'op-t1a'); // the first create keeps its id
        expect(
          jsonDecode(live['payload_json'] as String)['title'],
          'Final title',
        );
        final reasons = {
          for (final r in _all(
            db.raw,
            'SELECT operation_id, archive_reason FROM sync_outbox_archive',
          ))
            r['operation_id']: r['archive_reason'],
        };
        expect(reasons['op-t1a'], 'migrated_to_v2_create');
        expect(reasons['op-t1b'], 'folded_into_create');
      },
    );

    test(
      'ordering follows the verified v1 rowid order, never created_at_utc',
      () {
        final path = _path();
        // The clock went backwards: later rows carry earlier timestamps.
        createV1File(path, [
          "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
          v1Project('p1'),
          v1Project('p2'),
          v1Project('p3'),
          v1Op(
            'op-3',
            'project',
            'p3',
            v1ProjectPayload('p3'),
            createdAt: '2026-03-01T00:00:00.000Z',
          ),
          v1Op(
            'op-1',
            'project',
            'p1',
            v1ProjectPayload('p1'),
            createdAt: '2026-02-01T00:00:00.000Z',
          ),
          v1Op(
            'op-2',
            'project',
            'p2',
            v1ProjectPayload('p2'),
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        ]);

        final db = LocalDatabase.open(path);
        addTearDown(db.close);

        expect(
          _all(
            db.raw,
            'SELECT operation_id FROM sync_outbox ORDER BY seq',
          ).map((r) => r['operation_id']),
          ['op-3', 'op-1', 'op-2'],
        );
        expect(
          _all(
            db.raw,
            'SELECT operation_id FROM sync_outbox_archive ORDER BY id',
          ).map((r) => r['operation_id']),
          ['op-3', 'op-1', 'op-2'],
        );
      },
    );

    test('ambiguous states make the entity unclassified, with nothing replayed or reset', () {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        v1Project('p1', version: 5),
        v1Task('t-sent', 'p1', version: 2),
        v1Task('t-failed', 'p1', version: 3),
        v1Task('t-acked', 'p1', version: 7),
        v1Task('t-child', 'p1', parentId: 't-acked', version: 1),
        v1Op(
          'o1',
          'project',
          'p1',
          v1ProjectPayload('p1'),
          state: 'acked',
          attempts: 1,
        ),
        v1Op(
          'o2',
          'task',
          't-sent',
          v1TaskPayload('t-sent', 'p1'),
          state: 'sent',
          attempts: 2,
        ),
        v1Op(
          'o3',
          'task',
          't-failed',
          v1TaskPayload('t-failed', 'p1'),
          state: 'failed',
          attempts: 3,
          lastError: 'boom',
        ),
        v1Op(
          'o4',
          'task',
          't-acked',
          v1TaskPayload('t-acked', 'p1'),
          state: 'acked',
          attempts: 1,
        ),
        v1Op(
          'o5',
          'task',
          't-child',
          v1TaskPayload('t-child', 'p1', parentId: 't-acked'),
        ),
      ]);

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      final versions = {
        for (final r in _all(
          db.raw,
          'SELECT id, version, sync_scope FROM tasks',
        ))
          r['id']: [r['version'], r['sync_scope']],
      };
      expect(versions['t-sent'], [2, 'unclassified']);
      expect(versions['t-failed'], [3, 'unclassified']);
      expect(versions['t-acked'], [7, 'unclassified']);
      // A pending base-0 child of an unclassified parent is unclassified too.
      expect(versions['t-child'], [1, 'unclassified']);
      expect(_scalar(db.raw, 'SELECT COUNT(*) FROM sync_outbox'), 0);
      final archived = _all(
        db.raw,
        'SELECT * FROM sync_outbox_archive ORDER BY id',
      );
      expect(archived, hasLength(5));
      final failed = archived.firstWhere((r) => r['operation_id'] == 'o3');
      expect(failed['state'], 'failed');
      expect(failed['attempts'], 3);
      expect(failed['last_error'], 'boom');
      expect(failed['archive_reason'], 'unclassified_entity');
      expect(_all(db.raw, 'SELECT version FROM projects').single['version'], 5);
    });

    test('deletes, positive bases and edits after the last unsent payload stay unclassified', () {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        v1Project('p1'),
        v1Task('t-del', 'p1'),
        v1Task('t-base', 'p1', version: 4),
        v1Task('t-edit', 'p1', title: 'Edited after the last op'),
        v1Op('a', 'project', 'p1', v1ProjectPayload('p1')),
        v1Op('b', 'task', 't-del', v1TaskPayload('t-del', 'p1')),
        v1Op('c', 'task', 't-del', {'id': 't-del'}, operationType: 'delete'),
        v1Op('d', 'task', 't-base', v1TaskPayload('t-base', 'p1'), base: 4),
        v1Op(
          'e',
          'task',
          't-edit',
          v1TaskPayload('t-edit', 'p1', title: 'Old title'),
        ),
      ]);

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      final scopes = {
        for (final r in _all(db.raw, 'SELECT id, sync_scope FROM tasks'))
          r['id']: r['sync_scope'],
      };
      expect(scopes['t-del'], 'unclassified');
      expect(scopes['t-base'], 'unclassified');
      expect(scopes['t-edit'], 'unclassified');
      expect(db.migrationReport!.warnings, contains('W05:task:t-edit'));
      expect(
        _all(
          db.raw,
          'SELECT scope FROM (SELECT sync_scope AS scope FROM projects)',
        ).single['scope'],
        'synced',
      );
    });

    test('rows without any operation (demo-like) and orphan operations are unclassified or archived', () {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        "INSERT INTO meta (key, value) VALUES ('demo_seeded', '2026-01-01')",
        v1Project('demo', version: 1),
        v1Task('d1', 'demo'),
        v1Op('orphan', 'task', 'gone', v1TaskPayload('gone', 'demo')),
      ]);

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(_all(db.raw, 'SELECT sync_scope, version FROM projects').single, {
        'sync_scope': 'unclassified',
        'version': 1,
      });
      expect(_scalar(db.raw, 'SELECT COUNT(*) FROM sync_outbox'), 0);
      expect(
        _all(
          db.raw,
          'SELECT archive_reason FROM sync_outbox_archive',
        ).single['archive_reason'],
        'orphan_entity',
      );
    });

    test('NULL notes become empty text and the owner binding moves to meta.user_id', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(
        _scalar(db.raw, "SELECT COUNT(*) FROM tasks WHERE notes IS NULL"),
        0,
      );
      expect(
        _scalar(db.raw, "SELECT value FROM meta WHERE key = 'user_id'"),
        'owner-1',
      );
      db.bindUser('owner-1'); // the same user is accepted
      expect(
        () => db.bindUser('someone-else'),
        throwsA(isA<RepositoryException>()),
      );
    });
  });

  group('aborts leave the v1 file untouched', () {
    Future<void> expectAbort(String path, String code) async {
      final before = _digestOf(path);
      expect(
        () => LocalDatabase.open(path),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.message,
            'message',
            contains(code),
          ),
        ),
      );
      final raw = sqlite3.open(path);
      addTearDown(raw.close);
      expect(raw.userVersion, 1);
      expect(snapshotDigest(raw), before);
      expect(
        _scalar(
          raw,
          "SELECT COUNT(*) FROM sqlite_master WHERE name = 'sync_outbox_archive'",
        ),
        0,
      );
    }

    test('a title over 200 characters is never truncated', () async {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        v1Project('p1'),
        v1Task('t1', 'p1', title: 'x' * 201),
      ]);
      await expectAbort(path, 'title_too_long');
    });

    test('rows owned by two users abort as a binding mismatch', () async {
      final path = _path();
      createV1File(path, [
        v1Project('p1', owner: 'owner-1'),
        v1Project('p2', owner: 'owner-2'),
      ]);
      await expectAbort(path, 'binding_mismatch');
    });

    test('meta owner that differs from the rows aborts', () async {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'someone')",
        v1Project('p1', owner: 'owner-1'),
      ]);
      await expectAbort(path, 'binding_mismatch');
    });

    test('a foreign key violation aborts', () async {
      final path = _path();
      createV1File(path, [v1Project('p1')]);
      final raw = sqlite3.open(path);
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute(v1Task('t1', 'missing-project'));
      raw.close();
      await expectAbort(path, 'foreign_key_violation');
    });
  });

  group('backup', () {
    test('a verified backup of the exact v1 snapshot is written first', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());
      final before = _digestOf(path);

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      final backups = _backups(path);
      expect(backups, hasLength(1));
      expect(db.migrationReport!.backupFile, backups.single.path);
      expect(db.migrationReport!.digestBefore, before);
      final copy = sqlite3.open(backups.single.path, mode: OpenMode.readOnly);
      addTearDown(copy.close);
      expect(copy.userVersion, 1);
      expect(snapshotDigest(copy), before);
      expect(_scalar(copy, 'SELECT COUNT(*) FROM sync_outbox'), 3);
    });

    test('a failed migration keeps the backup, leaves v1, and a rerun adds another backup', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());
      final before = _digestOf(path);

      expect(
        () => LocalDatabase.open(
          path,
          onMigrationStep: (step) {
            if (step == 'applied') {
              throw StateError('injected');
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(_backups(path), hasLength(1));
      expect(_digestOf(path), before);

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(db.schemaVersion, 2);
      expect(
        _backups(path),
        hasLength(2),
      ); // nothing was deleted or overwritten
    });

    test('an unwritable backup location aborts before any change', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());
      final before = _digestOf(path);

      expect(
        () => LocalDatabase.open(
          path,
          backupDirectory: '${_dir.path}${Platform.pathSeparator}missing',
        ),
        throwsA(
          isA<RepositoryException>().having(
            (e) => e.message,
            'message',
            contains('backup_failed'),
          ),
        ),
      );

      final raw = sqlite3.open(path);
      addTearDown(raw.close);
      expect(raw.userVersion, 1);
      expect(snapshotDigest(raw), before);
    });

    test('a brand-new file needs no backup', () {
      final path = _path();
      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(db.schemaVersion, 2);
      expect(db.migrationReport!.backupFile, isNull);
      expect(_backups(path), isEmpty);
    });

    test('backups are never deleted by later opens', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());
      LocalDatabase.open(path).close();
      final backup = _backups(path).single;
      final stat = backup.statSync();

      for (var i = 0; i < 3; i++) {
        LocalDatabase.open(path).close();
      }

      expect(backup.existsSync(), isTrue);
      expect(backup.statSync().modified, stat.modified);
      expect(_backups(path), hasLength(1));
    });
  });

  group('failure at every step', () {
    const steps = [
      'locked',
      'prechecked',
      'backup_done',
      'classified',
      'tables_created',
      'domain_copied',
      'tables_swapped',
      'outbox_migrated',
      'applied',
      'before_commit',
    ];
    for (final failAt in steps) {
      test('a failure at "$failAt" rolls back to an intact v1 file', () {
        final path = _path();
        createV1File(path, cleanV1Workspace());
        final before = _digestOf(path);

        expect(
          () => LocalDatabase.open(
            path,
            onMigrationStep: (step) {
              if (step == failAt) {
                throw StateError('injected at $step');
              }
            },
          ),
          throwsA(isA<StateError>()),
        );

        final raw = sqlite3.open(path);
        addTearDown(raw.close);
        expect(raw.userVersion, 1);
        expect(snapshotDigest(raw), before);
        expect(
          _scalar(
            raw,
            "SELECT COUNT(*) FROM sqlite_master WHERE name IN ('sync_outbox_archive', 'projects_v2', 'tasks_v2')",
          ),
          0,
        );
        // The file migrates normally afterwards.
        final db = LocalDatabase.open(path);
        addTearDown(db.close);
        expect(db.schemaVersion, 2);
        expect(_scalar(db.raw, 'SELECT COUNT(*) FROM sync_outbox'), 3);
      });
    }
  });

  group('concurrency', () {
    test('while migrating, another connection cannot write but can read', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());
      var checked = false;

      final db = LocalDatabase.open(
        path,
        onMigrationStep: (step) {
          if (step != 'locked') {
            return;
          }
          final other = sqlite3.open(path);
          try {
            other.execute('PRAGMA busy_timeout = 0');
            expect(
              () => other.execute('BEGIN IMMEDIATE'),
              throwsA(isA<SqliteException>()),
            );
            expect(_scalar(other, 'SELECT COUNT(*) FROM projects'), 1);
            checked = true;
          } finally {
            other.close();
          }
        },
      );
      addTearDown(db.close);

      expect(checked, isTrue);
      expect(db.schemaVersion, 2);
    });

    test('a second opener of an already migrated file does nothing', () {
      final path = _path();
      createV1File(path, cleanV1Workspace());
      final first = LocalDatabase.open(path);
      addTearDown(first.close);
      final second = LocalDatabase.open(path);
      addTearDown(second.close);

      expect(second.migrationReport, isNull);
      expect(
        _scalar(second.raw, 'SELECT COUNT(*) FROM sync_outbox_archive'),
        3,
      );
      expect(_backups(path), hasLength(1));
    });
  });

  group('refusals and diagnostics', () {
    test('a file newer than this build is refused and left unchanged', () {
      final path = _path();
      LocalDatabase.open(path).close();
      final raw = sqlite3.open(path);
      raw.userVersion = 99;
      raw.close();

      expect(
        () => LocalDatabase.open(path),
        throwsA(isA<RepositoryException>()),
      );

      final check = sqlite3.open(path);
      addTearDown(check.close);
      expect(check.userVersion, 99);
    });

    test('the report and its table hold ids and counts only, never titles or notes', () {
      final path = _path();
      createV1File(path, [
        "INSERT INTO meta (key, value) VALUES ('owner_id', 'owner-1')",
        v1Project('p1', name: 'Secret project name'),
        v1Task('t1', 'p1', title: 'Secret task title', notes: 'secret notes'),
        v1Task('t2', 'p1', title: 'Another secret'),
        v1Op(
          'x1',
          'project',
          'p1',
          v1ProjectPayload('p1', name: 'Secret project name'),
        ),
        v1Op(
          'x2',
          'task',
          't1',
          v1TaskPayload('t1', 'p1', title: 'Older secret'),
          state: 'sent',
        ),
      ]);

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      final row = _all(db.raw, 'SELECT * FROM sync_migration_report').single;
      final text = jsonEncode(row);
      expect(text.contains('secret'), isFalse);
      expect(text.contains('Secret'), isFalse);
      expect(jsonDecode(row['counts_json'] as String)['v1_operations'], 2);
      expect(row['from_version'], 1);
      expect(row['to_version'], 2);
    });
  });

  group('v2 schema', () {
    late LocalDatabase db;

    setUp(() {
      db = LocalDatabase.open(_path());
      addTearDown(db.close);
      db.raw.execute(
        "INSERT INTO projects (id, owner_id, name, sort_order, version, sync_scope, created_at, updated_at) "
        "VALUES ('p1', 'o', 'P', 0, 0, 'synced', 't', 't'), ('p2', 'o', 'Q', 0, 0, 'synced', 't', 't')",
      );
    });

    Object? tryExecute(String sql, [List<Object?> params = const []]) {
      try {
        db.raw.execute(sql, params);
        return 'ok';
      } on SqliteException catch (error) {
        return error.message;
      }
    }

    const insert =
        'INSERT INTO sync_outbox (operation_id, entity_type, entity_id, op_type, '
        'observed_base_version, payload_json, payload_bytes, created_at_utc, depends_on_seq) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)';

    test('every table, index and trigger exists', () {
      final names = {
        for (final r in _all(db.raw, 'SELECT name FROM sqlite_master'))
          r['name'],
      };
      for (final expected in [
        'projects',
        'tasks',
        'meta',
        'sync_outbox',
        'sync_outbox_archive',
        'sync_entity_snapshot',
        'sync_conflicts_local',
        'sync_state',
        'sync_migration_report',
        'tasks_by_project',
        'sync_one_inflight',
        'sync_one_live_create',
        'sync_outbox_by_entity',
        'sync_outbox_by_state',
        'sync_outbox_identity_immutable',
        'sync_outbox_claimed_immutable',
        'sync_outbox_state_machine',
        'sync_outbox_result_write_once',
        'sync_outbox_handled_write_once',
        'sync_outbox_no_delete_claimed',
        'sync_outbox_archive_no_update',
        'sync_outbox_archive_no_delete',
        'sync_conflicts_evidence_immutable',
        'sync_conflicts_resolution_write_once',
        'sync_conflicts_no_delete',
        'tasks_project_immutable',
      ]) {
        expect(names, contains(expected), reason: expected);
      }
      expect(_all(db.raw, 'PRAGMA foreign_key_check'), isEmpty);
      expect(_scalar(db.raw, 'PRAGMA integrity_check'), 'ok');
    });

    test(
      'the rebuilt tasks table has foreign keys to the final table names',
      () {
        final fks = _all(db.raw, 'PRAGMA foreign_key_list(tasks)');
        expect(fks, hasLength(3));
        expect(fks.map((r) => r['table']).toSet(), {'tasks', 'projects'});
      },
    );

    test('a child whose parent is in another project is rejected by the composite key', () {
      db.raw.execute(
        "INSERT INTO tasks (id, project_id, owner_id, title, status, priority, version, sync_scope, created_at, updated_at) "
        "VALUES ('parent', 'p1', 'o', 'T', 'open', 'none', 0, 'synced', 't', 't')",
      );

      final result = tryExecute(
        "INSERT INTO tasks (id, project_id, owner_id, parent_id, title, status, priority, version, sync_scope, created_at, updated_at) "
        "VALUES ('child', 'p2', 'o', 'parent', 'T', 'open', 'none', 0, 'synced', 't', 't')",
      );

      expect(result, contains('FOREIGN KEY'));
    });

    test('sync_scope has no default and only three values', () {
      expect(
        tryExecute(
          "INSERT INTO projects (id, owner_id, name, created_at, updated_at) VALUES ('x', 'o', 'N', 't', 't')",
        ),
        contains('NOT NULL'),
      );
      expect(
        tryExecute(
          "INSERT INTO projects (id, owner_id, name, sync_scope, created_at, updated_at) VALUES ('x', 'o', 'N', 'bogus', 't', 't')",
        ),
        contains('CHECK'),
      );
    });

    test('a title over 200 characters is refused by the table', () {
      expect(
        tryExecute(
          "INSERT INTO tasks (id, project_id, owner_id, title, status, priority, version, sync_scope, created_at, updated_at) "
          "VALUES ('t', 'p1', 'o', ?, 'open', 'none', 0, 'synced', 't', 't')",
          ['x' * 201],
        ),
        contains('CHECK'),
      );
    });

    test('create must have base 0; update with base 0 needs a dependency; payload ceiling', () {
      expect(
        tryExecute(insert, ['a', 'task', 't', 'create', 1, '{}', 2, 't', null]),
        contains('CHECK'),
      );
      expect(
        tryExecute(insert, ['b', 'task', 't', 'update', 0, '{}', 2, 't', null]),
        contains('CHECK'),
      );
      expect(
        tryExecute(insert, [
          'c',
          'task',
          't',
          'create',
          0,
          '{}',
          229377,
          't',
          null,
        ]),
        contains('CHECK'),
      );
      expect(
        tryExecute(insert, ['d', 'task', 't', 'create', 0, '{}', 2, 't', null]),
        'ok',
      );
    });

    test('one live create and one in-flight operation per entity', () {
      expect(
        tryExecute(insert, ['a', 'task', 't', 'create', 0, '{}', 2, 't', null]),
        'ok',
      );
      expect(
        tryExecute(insert, ['b', 'task', 't', 'create', 0, '{}', 2, 't', null]),
        contains('UNIQUE'),
      );
      expect(
        tryExecute(insert, ['c', 'task', 't', 'update', 1, '{}', 2, 't', null]),
        'ok',
      );
      db.raw.execute(
        "UPDATE sync_outbox SET base_version = 0, state = 'in_flight' WHERE operation_id = 'a'",
      );
      expect(
        tryExecute(
          "UPDATE sync_outbox SET base_version = 1, state = 'in_flight' WHERE operation_id = 'c'",
        ),
        contains('UNIQUE'),
      );
    });

    test('identity, claimed payload and results are immutable; history is never deleted', () {
      expect(
        tryExecute(insert, ['a', 'task', 't', 'create', 0, '{}', 2, 't', null]),
        'ok',
      );
      expect(
        tryExecute(
          "UPDATE sync_outbox SET entity_id = 'x' WHERE operation_id = 'a'",
        ),
        contains('immutable'),
      );
      // Before the first claim the payload may still be edited (folding).
      expect(
        tryExecute(
          "UPDATE sync_outbox SET payload_json = '{\"a\":1}', payload_bytes = 7 WHERE operation_id = 'a'",
        ),
        'ok',
      );
      db.raw.execute(
        "UPDATE sync_outbox SET base_version = 0, state = 'in_flight' WHERE operation_id = 'a'",
      );
      expect(
        tryExecute(
          "UPDATE sync_outbox SET payload_json = '{}' WHERE operation_id = 'a'",
        ),
        contains('immutable'),
      );
      expect(
        tryExecute(
          "UPDATE sync_outbox SET state = 'pending' WHERE operation_id = 'a'",
        ),
        'ok',
      ); // requeue
      db.raw.execute(
        "UPDATE sync_outbox SET state = 'in_flight' WHERE operation_id = 'a'",
      );
      db.raw.execute(
        "UPDATE sync_outbox SET state = 'applied', applied_version = 1, version_before = 0 WHERE operation_id = 'a'",
      );
      expect(
        tryExecute(
          "UPDATE sync_outbox SET state = 'pending' WHERE operation_id = 'a'",
        ),
        contains('illegal'),
      );
      expect(
        tryExecute(
          "UPDATE sync_outbox SET applied_version = 9 WHERE operation_id = 'a'",
        ),
        contains('written once'),
      );
      expect(
        tryExecute("DELETE FROM sync_outbox WHERE operation_id = 'a'"),
        contains('never deleted'),
      );
    });

    test(
      'a pending, never-claimed operation may be deleted (archive first)',
      () {
        expect(
          tryExecute(insert, [
            'a',
            'task',
            't',
            'create',
            0,
            '{}',
            2,
            't',
            null,
          ]),
          'ok',
        );
        expect(
          tryExecute("DELETE FROM sync_outbox WHERE operation_id = 'a'"),
          'ok',
        );
      },
    );

    test('seq values are never reused', () {
      expect(
        tryExecute(insert, ['a', 'task', 't', 'create', 0, '{}', 2, 't', null]),
        'ok',
      );
      final first = _scalar(db.raw, 'SELECT MAX(seq) FROM sync_outbox') as int;
      db.raw.execute("DELETE FROM sync_outbox WHERE operation_id = 'a'");
      expect(
        tryExecute(insert, ['b', 'task', 't', 'create', 0, '{}', 2, 't', null]),
        'ok',
      );
      expect(
        _scalar(db.raw, 'SELECT MAX(seq) FROM sync_outbox') as int,
        greaterThan(first),
      );
    });

    test(
      'the archive and conflict evidence are append-only and write-once',
      () {
        db.raw.execute(
          "INSERT INTO sync_outbox_archive (source, archive_reason, operation_id, entity_type, entity_id, operation_type, payload_json, created_at_utc, state, attempts, archived_at_utc) "
          "VALUES ('v1', 'x', 'z', 'task', 't', 'upsert', '{}', 't', 'pending', 0, 't')",
        );
        expect(
          tryExecute("UPDATE sync_outbox_archive SET archive_reason = 'y'"),
          contains('append-only'),
        );
        expect(
          tryExecute('DELETE FROM sync_outbox_archive'),
          contains('append-only'),
        );
        db.raw.execute(
          "INSERT INTO sync_conflicts_local (id, operation_id, entity_type, entity_id, kind, fields_json, base_version, server_version, server_value_json, client_value_json, created_at_utc) "
          "VALUES ('c1', 'o1', 'task', 't', 'field', '[]', 1, 2, '{}', '{}', 't')",
        );
        expect(
          tryExecute(
            "UPDATE sync_conflicts_local SET kind = 'exists' WHERE id = 'c1'",
          ),
          contains('immutable'),
        );
        db.raw.execute(
          "UPDATE sync_conflicts_local SET status = 'resolved_server', resolution_source = 'x', resolved_at_utc = 't' WHERE id = 'c1'",
        );
        expect(
          tryExecute(
            "UPDATE sync_conflicts_local SET status = 'open' WHERE id = 'c1'",
          ),
          contains('written once'),
        );
        expect(
          tryExecute("DELETE FROM sync_conflicts_local WHERE id = 'c1'"),
          contains('never deleted'),
        );
      },
    );

    test('a task cannot move to another project', () {
      db.raw.execute(
        "INSERT INTO tasks (id, project_id, owner_id, title, status, priority, version, sync_scope, created_at, updated_at) "
        "VALUES ('t', 'p1', 'o', 'T', 'open', 'none', 0, 'synced', 't', 't')",
      );
      expect(
        tryExecute("UPDATE tasks SET project_id = 'p2' WHERE id = 't'"),
        contains('cannot move'),
      );
    });
  });

  group('snapshot digest', () {
    test('depends on row order and content, not on rowid values', () {
      final a = sqlite3.openInMemory();
      final b = sqlite3.openInMemory();
      final c = sqlite3.openInMemory();
      addTearDown(a.close);
      addTearDown(b.close);
      addTearDown(c.close);
      for (final db in [a, b, c]) {
        db.execute(
          'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        db.execute('CREATE TABLE projects (id TEXT PRIMARY KEY, name TEXT)');
        db.execute('CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT)');
        db.execute(
          'CREATE TABLE sync_outbox (operation_id TEXT PRIMARY KEY, n INTEGER)',
        );
      }
      a.execute("INSERT INTO sync_outbox VALUES ('x', 1), ('y', 2)");
      b.execute("INSERT INTO sync_outbox VALUES ('x', 1), ('y', 2)");
      b.execute("DELETE FROM sync_outbox WHERE operation_id = 'y'");
      b.execute(
        "INSERT INTO sync_outbox (rowid, operation_id, n) VALUES (50, 'y', 2)",
      );
      c.execute("INSERT INTO sync_outbox VALUES ('y', 2), ('x', 1)");

      expect(snapshotDigest(a), snapshotDigest(b)); // same rows, same order
      expect(snapshotDigest(a), isNot(snapshotDigest(c))); // order differs
      a.execute("UPDATE sync_outbox SET n = 3 WHERE operation_id = 'x'");
      expect(snapshotDigest(a), isNot(snapshotDigest(b))); // content differs
    });
  });
}
