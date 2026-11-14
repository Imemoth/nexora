import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';

import 'strings/app_strings.dart';
import 'theme/theme_scope.dart';

/// Light, Dark and System choice. Selecting one restyles the app at once and
/// saves the choice. It never touches the task workspace.
class ThemeSelector extends StatelessWidget {
  const ThemeSelector({super.key});

  static IconData _iconFor(ThemePreference preference) {
    return switch (preference) {
      ThemePreference.light => Icons.light_mode_outlined,
      ThemePreference.dark => Icons.dark_mode_outlined,
      ThemePreference.system => Icons.desktop_windows_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final controller = ThemeScope.maybeOf(context);
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return Semantics(
      label: AppStrings.themeLabel,
      child: SegmentedButton<ThemePreference>(
        key: const ValueKey('theme-selector'),
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
        segments: [
          for (final preference in ThemePreference.values)
            ButtonSegment<ThemePreference>(
              value: preference,
              icon: Icon(_iconFor(preference), size: 16),
              label: Text(AppStrings.themeLabelOf(preference)),
            ),
        ],
        selected: {controller.preference},
        onSelectionChanged: (selection) => controller.select(selection.first),
      ),
    );
  }
}
