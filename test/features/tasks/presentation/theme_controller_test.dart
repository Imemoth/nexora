import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/theme.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

void main() {
  test('System is the default and follows the platform', () {
    final controller = ThemeController(InMemorySettingsStore());
    expect(controller.preference, ThemePreference.system);
    expect(controller.mode, ThemeMode.system);
  });

  test(
    'a choice applies at once, is saved and is loaded on the next start',
    () async {
      final store = InMemorySettingsStore();
      final controller = ThemeController(store);
      var notified = 0;
      controller.addListener(() => notified++);
      await controller.select(ThemePreference.light);
      expect(controller.mode, ThemeMode.light);
      expect(notified, 1);
      expect(await store.loadThemePreference(), ThemePreference.light);

      final next = ThemeController(store);
      await next.load();
      expect(next.preference, ThemePreference.light);
    },
  );

  test('choosing the current theme again does nothing', () async {
    final controller = ThemeController(InMemorySettingsStore());
    var notified = 0;
    controller.addListener(() => notified++);
    await controller.select(ThemePreference.system);
    expect(notified, 0);
  });

  test('both themes carry their own colours and the same structure', () {
    final dark = buildNexoraDarkTheme();
    final light = buildNexoraLightTheme();
    expect(dark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
    expect(dark.extension<NexoraColors>()!.isDark, isTrue);
    expect(light.extension<NexoraColors>()!.isDark, isFalse);
    expect(dark.scaffoldBackgroundColor, NexoraColors.dark.background);
    expect(light.scaffoldBackgroundColor, NexoraColors.light.background);
  });
}
