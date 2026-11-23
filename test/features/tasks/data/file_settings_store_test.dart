import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/data/file_settings_store.dart';

late Directory _dir;

File get _file => File('${_dir.path}${Platform.pathSeparator}settings.json');

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('nexora-settings-test-');
  });

  tearDown(() {
    _dir.deleteSync(recursive: true);
  });

  test('defaults to System when nothing was saved', () async {
    expect(
      await FileSettingsStore(_file).loadThemePreference(),
      ThemePreference.system,
    );
  });

  test('keeps the saved preference for the next start', () async {
    await FileSettingsStore(_file).saveThemePreference(ThemePreference.light);

    expect(
      await FileSettingsStore(_file).loadThemePreference(),
      ThemePreference.light,
    );
  });

  test('a later save replaces the earlier choice', () async {
    final store = FileSettingsStore(_file);
    await store.saveThemePreference(ThemePreference.light);
    await store.saveThemePreference(ThemePreference.dark);

    expect(await store.loadThemePreference(), ThemePreference.dark);
  });

  test(
    'a damaged file falls back to System and is repaired by a save',
    () async {
      _file.writeAsStringSync('{ not json');
      final store = FileSettingsStore(_file);

      expect(await store.loadThemePreference(), ThemePreference.system);

      await store.saveThemePreference(ThemePreference.dark);
      expect(await store.loadThemePreference(), ThemePreference.dark);
    },
  );

  test('an unknown stored value falls back to System', () async {
    _file.writeAsStringSync('{"theme_preference":"sepia"}');

    expect(
      await FileSettingsStore(_file).loadThemePreference(),
      ThemePreference.system,
    );
  });

  test('creates the folder when it does not exist yet', () async {
    final nested = File(
      '${_dir.path}${Platform.pathSeparator}new${Platform.pathSeparator}settings.json',
    );

    await FileSettingsStore(nested).saveThemePreference(ThemePreference.dark);

    expect(nested.existsSync(), isTrue);
  });
}
