import 'dart:convert';
import 'dart:io';

import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';

/// Keeps device settings in one small JSON file in the app's data folder, next
/// to the local database. It is deliberately not inside any database: a
/// signed-in account opens its own database, and the theme belongs to the
/// device, so it must not change when the account does. Settings never sync.
final class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this._file);

  static const _themeKey = 'theme_preference';

  final File _file;

  @override
  Future<ThemePreference> loadThemePreference() async {
    final value = _read()[_themeKey];
    for (final preference in ThemePreference.values) {
      if (preference.name == value) {
        return preference;
      }
    }
    return ThemePreference.system;
  }

  @override
  Future<void> saveThemePreference(ThemePreference preference) async {
    try {
      final settings = _read()..[_themeKey] = preference.name;
      if (!_file.parent.existsSync()) {
        _file.parent.createSync(recursive: true);
      }
      // Write beside the file and rename, so a crash never leaves half a file.
      final temp = File('${_file.path}.tmp');
      temp.writeAsStringSync(jsonEncode(settings), flush: true);
      temp.renameSync(_file.path);
    } on FileSystemException catch (error) {
      throw RepositoryException(error.message);
    }
  }

  /// The stored settings, or an empty map when the file is missing or unreadable.
  /// A damaged settings file falls back to defaults and is replaced on the next
  /// save; it never blocks startup.
  Map<String, Object?> _read() {
    try {
      if (!_file.existsSync()) {
        return <String, Object?>{};
      }
      final decoded = jsonDecode(_file.readAsStringSync());
      return decoded is Map<String, Object?>
          ? Map<String, Object?>.of(decoded)
          : <String, Object?>{};
    } on FileSystemException {
      return <String, Object?>{};
    } on FormatException {
      return <String, Object?>{};
    }
  }
}
