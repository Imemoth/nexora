import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:sqlite3/sqlite3.dart';

import 'local_database.dart';

/// Keeps the theme preference in the existing `meta` table. No schema change,
/// no outbox entry: settings are local to this device and never sync.
final class SqliteSettingsStore implements SettingsStore {
  SqliteSettingsStore(this._db);

  static const _themeKey = 'theme_preference';

  final LocalDatabase _db;

  @override
  Future<ThemePreference> loadThemePreference() async {
    try {
      final rows = _db.raw.select('SELECT value FROM meta WHERE key = ?', [
        _themeKey,
      ]);
      if (rows.isEmpty) {
        return ThemePreference.system;
      }
      final value = rows.single['value'] as String;
      for (final preference in ThemePreference.values) {
        if (preference.name == value) {
          return preference;
        }
      }
      return ThemePreference.system;
    } on SqliteException catch (error) {
      throw RepositoryException(error.message);
    }
  }

  @override
  Future<void> saveThemePreference(ThemePreference preference) async {
    try {
      _db.raw.execute(
        'INSERT INTO meta (key, value) VALUES (?, ?) '
        'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
        [_themeKey, preference.name],
      );
    } on SqliteException catch (error) {
      throw RepositoryException(error.message);
    }
  }
}
