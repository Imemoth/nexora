/// The user's theme choice. [system] follows the Windows appearance setting.
enum ThemePreference { light, dark, system }

/// Stores app settings on this device. Implementations throw
/// `RepositoryException` when a call cannot complete.
abstract interface class SettingsStore {
  /// The saved preference, or [ThemePreference.system] when none was saved.
  Future<ThemePreference> loadThemePreference();

  Future<void> saveThemePreference(ThemePreference preference);
}

/// Keeps the preference in memory only. Used by tests and as the default when
/// no durable store is supplied.
final class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([this._preference = ThemePreference.system]);

  ThemePreference _preference;

  @override
  Future<ThemePreference> loadThemePreference() async => _preference;

  @override
  Future<void> saveThemePreference(ThemePreference preference) async {
    _preference = preference;
  }
}
