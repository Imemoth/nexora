import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

/// UI font stacks. The V2 design uses Manrope for text and Space Grotesk for
/// the brand, titles and numerals. Both ship in `assets/fonts` (SIL Open Font
/// License) and are declared in `pubspec.yaml`. Segoe UI is the fallback.
const String nexoraTextFont = 'Manrope';
const String nexoraDisplayFont = 'Space Grotesk';
const List<String> nexoraFontFallback = ['Segoe UI'];

/// The approved dark theme.
ThemeData buildNexoraDarkTheme() => buildNexoraTheme(Brightness.dark);

/// The approved light theme: the same structure as dark with its own tokens.
ThemeData buildNexoraLightTheme() => buildNexoraTheme(Brightness.light);

ThemeData buildNexoraTheme(Brightness brightness) {
  final c = brightness == Brightness.dark
      ? NexoraColors.dark
      : NexoraColors.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accentBlue,
    onPrimary: c.onAccent,
    secondary: c.accentCyan,
    onSecondary: c.onAccent,
    tertiary: c.accentViolet,
    onTertiary: c.onAccent,
    error: c.statusOverdue,
    onError: c.onAccent,
    surface: c.surface,
    onSurface: c.text1,
    onSurfaceVariant: c.text2,
    outline: c.borderStrong,
    outlineVariant: c.border,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.panel,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surface2,
    surfaceContainerHighest: c.surface2,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
  );
  final text = base.textTheme
      .apply(bodyColor: c.text1, displayColor: c.text1)
      .copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: nexoraDisplayFont,
          fontWeight: FontWeight.w700,
          color: c.text1,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: nexoraDisplayFont,
          fontWeight: FontWeight.w700,
          color: c.text1,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: c.text1,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: c.text2,
        ),
      );

  final focusRing = BorderSide(color: c.accentCyan, width: 2);
  final fieldBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: c.borderStrong),
  );

  return base.copyWith(
    extensions: [c],
    textTheme: text,
    scaffoldBackgroundColor: c.background,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    focusColor: c.accentCyan.withValues(alpha: 0.2),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: c.borderStrong),
      ),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.text2),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.borderStrong),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surface2,
      contentTextStyle: text.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.borderStrong),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.text2,
      textColor: c.text1,
      selectedColor: c.text1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.transparent),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.accentBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.statusOverdue),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c.statusOverdue, width: 2),
      ),
      hintStyle: TextStyle(color: c.textMuted),
      labelStyle: TextStyle(color: c.text2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            foregroundColor: c.onAccent,
            backgroundColor: c.accentBlue,
            minimumSize: const Size(64, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? focusRing
                  : BorderSide.none,
            ),
            backgroundBuilder: (context, states, child) {
              if (states.contains(WidgetState.disabled)) {
                return child ?? const SizedBox.shrink();
              }
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: c.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: child,
              );
            },
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            foregroundColor: c.accentCyan,
            minimumSize: const Size(64, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused)
                  ? focusRing
                  : BorderSide.none,
            ),
          ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text1,
        minimumSize: const Size(64, 44),
        side: BorderSide(color: c.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.text2),
    ),
  );
}
