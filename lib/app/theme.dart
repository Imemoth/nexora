import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/theme/palette.dart';

/// The approved dark theme. It is the only theme in Phase 1.
ThemeData buildNexoraDarkTheme() {
  final scheme = ColorScheme.dark(
    primary: const Color(NexoraPalette.primary),
    onPrimary: const Color(NexoraPalette.background),
    surface: const Color(NexoraPalette.surface),
    onSurface: const Color(NexoraPalette.text1),
    outline: const Color(NexoraPalette.border),
    error: const Color(NexoraPalette.negative),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(NexoraPalette.background),
    dividerColor: const Color(NexoraPalette.border),
  );
}
