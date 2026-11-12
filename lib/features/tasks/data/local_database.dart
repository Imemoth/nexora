import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migrations.dart';

/// The local SQLite file. Opening it applies pending migrations.
///
/// A file written by a newer app version is refused and left unchanged. The
/// database is never reset or reseeded here.
final class LocalDatabase {
  LocalDatabase._(this.raw, this.schemaVersion);

  /// The schema version this build understands.
  static const int currentVersion = 1;

  /// The raw handle. Repository code uses it inside transactions.
  final Database raw;

  /// The schema version of the open file.
  final int schemaVersion;

  /// Opens (creating if absent) the file at [path] and migrates it.
  static LocalDatabase open(String path) {
    final Database raw;
    try {
      raw = sqlite3.open(path);
    } on SqliteException catch (error) {
      throw RepositoryException('open failed: ${error.message}');
    }
    try {
      raw.execute('PRAGMA foreign_keys = ON;');
      raw.execute('PRAGMA busy_timeout = 5000;');
      raw.execute('PRAGMA journal_mode = WAL;');
      raw.execute('PRAGMA synchronous = FULL;');
      final version = raw.userVersion;
      if (version > currentVersion) {
        raw.dispose();
        throw RepositoryException(
          'database schema $version is newer than supported $currentVersion',
        );
      }
      _migrate(raw, from: version);
      return LocalDatabase._(raw, currentVersion);
    } on SqliteException catch (error) {
      raw.dispose();
      throw RepositoryException('migration failed: ${error.message}');
    }
  }

  /// Closes the file. The object must not be used afterwards.
  void close() {
    raw.dispose();
  }

  static void _migrate(Database raw, {required int from}) {
    for (var target = from + 1; target <= currentVersion; target++) {
      raw.execute('BEGIN IMMEDIATE;');
      try {
        for (final statement in migrationStatements[target - 1]) {
          raw.execute(statement);
        }
        raw.userVersion = target;
        raw.execute('COMMIT;');
      } catch (_) {
        raw.execute('ROLLBACK;');
        rethrow;
      }
    }
  }
}
