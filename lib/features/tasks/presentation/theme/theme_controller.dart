import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';

/// Holds the user's theme choice and saves it on this device.
///
/// It is separate from the task workspace on purpose: changing the theme only
/// restyles the app. It never touches selection, drafts or the unsaved-change
/// gate, so editing continues uninterrupted.
final class ThemeController extends ChangeNotifier {
  ThemeController(
    this._store, {
    ThemePreference initial = ThemePreference.system,
  }) : _preference = initial;

  final SettingsStore _store;
  ThemePreference _preference;

  ThemePreference get preference => _preference;

  /// `ThemeMode.system` follows the Windows appearance setting, including
  /// changes while the app runs.
  ThemeMode get mode => switch (_preference) {
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.system => ThemeMode.system,
  };

  /// Reads the saved preference. A read failure keeps the current value.
  Future<void> load() async {
    try {
      final saved = await _store.loadThemePreference();
      if (saved != _preference) {
        _preference = saved;
        notifyListeners();
      }
    } on RepositoryException {
      // Keep the default. The app stays usable without a saved preference.
    }
  }

  /// Applies [preference] at once, then saves it. A failed save keeps the
  /// choice for this session.
  Future<void> select(ThemePreference preference) async {
    if (preference == _preference) {
      return;
    }
    _preference = preference;
    notifyListeners();
    try {
      await _store.saveThemePreference(preference);
    } on RepositoryException {
      // The choice still applies until the app closes.
    }
  }
}
