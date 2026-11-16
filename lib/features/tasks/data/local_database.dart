import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migration_v2.dart';
import 'migrations.dart';
import 'schema_v3.dart';
import 'schema_v4.dart';
import 'schema_v5.dart';
import 'schema_v6.dart';

export 'migration_v2.dart' show MigrationReport, MigrationStepHook;

/// The local SQLite file. Opening it applies pending migrations.
///
/// A file written by a newer app version is refused and left unchanged. The
/// database is never reset or reseeded here. Migrating an existing version 1
/// file to version 2 first writes a verified backup next to the file (or into
/// [open]'s `backupDirectory`); backups are never deleted automatically.
final class LocalDatabase {
  LocalDatabase._(this.raw, this.schemaVersion, this.migrationReport);

  /// The schema version this build understands.
  static const int currentVersion = 6;

  /// The raw handle. Repository code uses it inside transactions.
  final Database raw;

  /// The schema version of the open file.
  final int schemaVersion;

  /// What the migration did during this [open], or null when none ran.
  final MigrationReport? migrationReport;

  /// Opens (creating if absent) the file at [path] and migrates it.
  ///
  /// [onMigrationStep] and [backupDirectory] exist for tests: the first lets a
  /// test fail the migration at a named point, the second moves the backup.
  static LocalDatabase open(
    String path, {
    MigrationStepHook? onMigrationStep,
    String? backupDirectory,
    DateTime Function()? now,
  }) {
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
        throw RepositoryException(
          'database schema $version is newer than supported $currentVersion',
        );
      }
      if (version < 1) {
        _applyVersion1(raw);
      }
      MigrationReport? report;
      if (version < 2) {
        report = MigrationV2(
          raw,
          path,
          onStep: onMigrationStep,
          backupDirectory: backupDirectory,
          now: now,
        ).run(createBackup: version == 1);
      }
      if (version < 3) {
        _applyVersion3(raw);
      }
      if (version < 4) {
        _applyVersion4(raw);
      }
      if (version < 5) {
        _applyVersion5(raw);
      }
      if (version < 6) {
        _applyVersion6(raw);
      }
      return LocalDatabase._(raw, currentVersion, report);
    } on SqliteException catch (error) {
      raw.close();
      throw RepositoryException('migration failed: ${error.message}');
    } on Object {
      raw.close();
      rethrow;
    }
  }

  /// The path of the open file (as SQLite reports it).
  String get filePath =>
      raw.select('PRAGMA database_list').first['file'] as String;

  /// Closes the file. The object must not be used afterwards.
  void close() {
    raw.close();
  }

  /// Binds the file to [userId] (`meta.user_id`), or checks an existing binding.
  /// A file bound to another user is refused and left unchanged.
  void bindUser(String userId) {
    final rows = raw.select("SELECT value FROM meta WHERE key = 'user_id'");
    if (rows.isEmpty) {
      raw.execute("INSERT INTO meta (key, value) VALUES ('user_id', ?)", [
        userId,
      ]);
      return;
    }
    if (rows.single['value'] != userId) {
      throw const RepositoryException('database belongs to another user');
    }
  }

  /// Migration 1: the original schema (frozen, see `migrations.dart`).
  static void _applyVersion1(Database raw) {
    raw.execute('BEGIN IMMEDIATE;');
    try {
      for (final statement in migrationStatements[0]) {
        raw.execute(statement);
      }
      raw.userVersion = 1;
      raw.execute('COMMIT;');
    } catch (_) {
      raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Migration 3: one additive table (see `schema_v3.dart`).
  static void _applyVersion3(Database raw) {
    raw.execute('BEGIN IMMEDIATE;');
    try {
      for (final statement in schemaV3Statements) {
        raw.execute(statement);
      }
      raw.userVersion = 3;
      raw.execute('COMMIT;');
    } catch (_) {
      raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Migration 4: one additive table for device-local reminders (see
  /// `schema_v4.dart`).
  static void _applyVersion4(Database raw) {
    raw.execute('BEGIN IMMEDIATE;');
    try {
      for (final statement in schemaV4Statements) {
        raw.execute(statement);
      }
      raw.userVersion = 4;
      raw.execute('COMMIT;');
    } catch (_) {
      raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Migration 5: one additive table (see `schema_v5.dart`).
  static void _applyVersion5(Database raw) {
    raw.execute('BEGIN IMMEDIATE;');
    try {
      for (final statement in schemaV5Statements) {
        raw.execute(statement);
      }
      raw.userVersion = 5;
      raw.execute('COMMIT;');
    } catch (_) {
      raw.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Migration 6: the due time becomes a column of `tasks` (see `schema_v6.dart`).
  static void _applyVersion6(Database raw) {
    raw.execute('BEGIN IMMEDIATE;');
    try {
      for (final statement in schemaV6Statements) {
        raw.execute(statement);
      }
      raw.userVersion = 6;
      raw.execute('COMMIT;');
    } catch (_) {
      raw.execute('ROLLBACK;');
      rethrow;
    }
  }
}
