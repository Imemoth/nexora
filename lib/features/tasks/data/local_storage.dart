import 'dart:io';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';

import 'local_database.dart';

/// The approved database location (owner decision D6):
/// `%LOCALAPPDATA%\Nexora\nexora.db`. The portable ZIP stays immutable, and data
/// survives re-extraction. `NEXORA_DB_PATH` overrides the location for tests and
/// the restart check.
String localDatabasePath(Map<String, String> environment) {
  final override = environment['NEXORA_DB_PATH'];
  if (override != null && override.isNotEmpty) {
    return override;
  }
  final base = environment['LOCALAPPDATA'];
  if (base == null || base.isEmpty) {
    throw RepositoryException('LOCALAPPDATA is not set');
  }
  return '$base${Platform.pathSeparator}Nexora${Platform.pathSeparator}nexora.db';
}

/// Creates the folder that holds [path], if it does not exist.
void ensureParentFolder(String path) {
  final folder = File(path).parent;
  if (!folder.existsSync()) {
    folder.createSync(recursive: true);
  }
}

/// The stable local owner id. It is created once and kept in the database, so
/// every later launch reads the same owner.
String ownerIdOf(LocalDatabase db, IdGenerator ids) {
  final rows = db.raw.select("SELECT value FROM meta WHERE key = 'owner_id'");
  if (rows.isNotEmpty) {
    return rows.single['value'] as String;
  }
  final id = ids.nextId();
  db.raw.execute("INSERT INTO meta (key, value) VALUES ('owner_id', ?)", [id]);
  return id;
}
