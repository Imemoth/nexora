import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/migrations.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../support/sha256.dart';

/// S5-0 safety net. Migration v1 has shipped to Windows installs, so it is
/// frozen: a v2 migration (S5) must be added next to it, never in place of it.
/// These tests fail if anything changes the v1 statements or the schema they
/// produce, and they prove a v1 file with synthetic data opens unchanged.
///
/// The golden values were produced by an independent script (see
/// test/fixtures/v1/PROVENANCE.md), not by this code.
const _goldenStatementsSha256 =
    'aa530b447af3cbf49d64bb237caaf41f15772a057c30451a3b005356fe08f5f5';
const _statementSeparator = '\n-- next statement --\n';

String _fixture(String name) => File('test/fixtures/v1/$name').readAsStringSync();

String _schemaFingerprint(Database db) {
  return db
      .select(
        'SELECT type, name, tbl_name, sql FROM sqlite_master '
        'WHERE sql IS NOT NULL ORDER BY type, name',
      )
      .map((r) => '${r['type']}|${r['name']}|${r['tbl_name']}|${r['sql']}')
      .join('\n');
}

Map<String, List<Object?>> _dump(Database db) {
  return {
    for (final table in ['meta', 'projects', 'tasks', 'sync_outbox'])
      table: db
          .select('SELECT * FROM $table ORDER BY rowid')
          .map((r) => [for (final key in r.keys) '$key=${r[key]}'].join(','))
          .toList(),
  };
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nexora-golden-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the SHA-256 helper matches the published test vectors', () {
    expect(
      sha256Hex('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(
      sha256Hex(''),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
    expect(
      sha256Hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
  });

  group('migration v1 is frozen', () {
    test('there is exactly one migration and its statement text is unchanged', () {
      expect(migrationStatements, hasLength(1));
      final canonical = migrationStatements.single.join(_statementSeparator);
      expect(canonical, _fixture('v1_migration_statements.golden.txt'));
      expect(sha256Hex(canonical), _goldenStatementsSha256);
    });

    test('a new file gets exactly the golden v1 schema', () {
      final db = LocalDatabase.open('${dir.path}/new.db');
      addTearDown(db.close);

      expect(db.raw.userVersion, 1);
      expect(_schemaFingerprint(db.raw), _fixture('v1_schema_fingerprint.golden.txt'));
    });

    test('the frozen synthetic fixture has the same schema as the app creates', () {
      final raw = sqlite3.open('${dir.path}/fixture.db');
      addTearDown(raw.close);
      raw.execute(_fixture('synthetic_v1.sql'));

      expect(_schemaFingerprint(raw), _fixture('v1_schema_fingerprint.golden.txt'));
    });
  });

  group('a v1 file with synthetic data', () {
    test('opens at v1 without any change to its rows, versions or outbox', () {
      final path = '${dir.path}/legacy.db';
      final seed = sqlite3.open(path);
      seed.execute(_fixture('synthetic_v1.sql'));
      seed.userVersion = 1;
      final before = _dump(seed);
      seed.close();

      final db = LocalDatabase.open(path);
      addTearDown(db.close);

      expect(db.schemaVersion, LocalDatabase.currentVersion);
      expect(db.raw.userVersion, LocalDatabase.currentVersion);
      expect(_dump(db.raw), before);
      expect(before['sync_outbox'], hasLength(5));
      expect(before['projects'], hasLength(2));
      expect(before['tasks'], hasLength(3));
    });

    test('the synthetic outbox covers every v1 state and pending-create base 0', () {
      final raw = sqlite3.open(':memory:');
      addTearDown(raw.close);
      raw.execute(_fixture('synthetic_v1.sql'));

      final states = raw
          .select('SELECT DISTINCT state FROM sync_outbox')
          .map((r) => r['state'])
          .toSet();
      expect(states, {'pending', 'sent', 'acked', 'failed'});
      expect(
        raw.select(
          "SELECT COUNT(*) AS n FROM sync_outbox WHERE base_version = 0 AND operation_type = 'upsert'",
        ).single['n'],
        greaterThan(0),
      );
    });
  });
}
