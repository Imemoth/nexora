import 'package:flutter/material.dart';
import 'package:nexora/features/tasks/presentation/theme/nexora_colors.dart';

/// Font stacks. Manrope for text, Space Grotesk for titles and numbers. Both
/// are bundled in `assets/fonts` (SIL Open Font License). Segoe UI is the
/// fallback.
const String nexoraTextFont = 'Manrope';
const String nexoraDisplayFont = 'Space Grotesk';
const List<String> nexoraFontFallback = ['Segoe UI'];

/// The Midnight type styles. Colours are applied by the widget (or by the
/// theme for the Material slots), so these carry size, weight and family only.
abstract final class NexoraText {
  static const displayStat = TextStyle(
    fontFamily: nexoraDisplayFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 30,
    height: 38 / 30,
    fontWeight: FontWeight.w600,
  );
  static const titlePage = TextStyle(
    fontFamily: nexoraDisplayFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w600,
  );
  static const titleDialog = TextStyle(
    fontFamily: nexoraDisplayFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 20,
    height: 28 / 20,
    fontWeight: FontWeight.w600,
  );
  static const titleField = TextStyle(
    fontFamily: nexoraDisplayFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 18,
    height: 24 / 18,
    fontWeight: FontWeight.w600,
  );
  static const bodyStrong = TextStyle(
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w700,
  );
  static const body = TextStyle(
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w500,
  );
  static const label = TextStyle(
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
  );
  static const caption = TextStyle(
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
  );
  static const overline = TextStyle(
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.72,
  );
  static const keycap = TextStyle(
    fontFamily: nexoraTextFont,
    fontFamilyFallback: nexoraFontFallback,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w700,
  );
}

/// The approved dark theme.
ThemeData buildNexoraDarkTheme() => buildNexoraTheme(Brightness.dark);

/// The approved light theme: the same structure as dark with its own tokens.
ThemeData buildNexoraLightTheme() => buildNexoraTheme(Brightness.light);

/// One theme for [brightness]. Layout never branches on the theme; only token
/// values differ.
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
        headlineSmall: NexoraText.titleDialog.copyWith(color: c.text1),
        titleLarge: NexoraText.titlePage.copyWith(color: c.text1),
        titleMedium: NexoraText.bodyStrong.copyWith(color: c.text1),
        bodyMedium: NexoraText.body.copyWith(color: c.text1),
        bodySmall: NexoraText.caption.copyWith(color: c.text2),
        labelLarge: NexoraText.bodyStrong,
        labelMedium: NexoraText.label.copyWith(color: c.text2),
        labelSmall: NexoraText.caption.copyWith(color: c.textMuted),
      );

  final focusRing = BorderSide(color: c.accentCyan, width: 2);
  OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  );
  final focusSide = WidgetStateProperty.resolveWith<BorderSide?>(
    (states) => states.contains(WidgetState.focused) ? focusRing : null,
  );

  return base.copyWith(
    extensions: [c],
    textTheme: text,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.panel,
    dividerColor: c.border,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    focusColor: c.accentCyan.withValues(alpha: 0.2),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: c.overlayShadow.first.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.borderStrong),
      ),
      titleTextStyle: NexoraText.titleDialog.copyWith(color: c.text1),
      contentTextStyle: NexoraText.body.copyWith(color: c.text2),
      insetPadding: const EdgeInsets.all(24),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: c.overlayShadow.first.color,
      textStyle: NexoraText.body.copyWith(color: c.text1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.borderStrong),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(c.overlayShadow.first.color),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.borderStrong),
          ),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.text1,
      contentTextStyle: NexoraText.body.copyWith(color: c.background),
      actionTextColor: c.accentBlue,
      behavior: SnackBarBehavior.floating,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.borderStrong),
      ),
      textStyle: NexoraText.caption.copyWith(color: c.text1),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.text2,
      textColor: c.text1,
      selectedColor: c.text1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.transparent),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: fieldBorder(c.borderStrong),
      enabledBorder: fieldBorder(c.borderStrong),
      focusedBorder: fieldBorder(c.accentCyan, 2),
      errorBorder: fieldBorder(c.statusOverdue),
      focusedErrorBorder: fieldBorder(c.statusOverdue, 2),
      hintStyle: NexoraText.body.copyWith(color: c.textMuted),
      labelStyle: NexoraText.label.copyWith(color: c.textMuted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      errorStyle: NexoraText.caption.copyWith(color: c.statusOverdue),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: c.onAccent,
        backgroundColor: c.accentBlue,
        disabledBackgroundColor: c.accentBlue.withValues(alpha: 0.45),
        disabledForegroundColor: c.onAccent.withValues(alpha: 0.45),
        minimumSize: const Size(64, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: buttonShape,
        textStyle: NexoraText.bodyStrong,
      ).copyWith(side: focusSide),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: c.text1,
            disabledForegroundColor: c.text1.withValues(alpha: 0.45),
            minimumSize: const Size(64, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            side: BorderSide(color: c.borderStrong),
            shape: buttonShape,
            textStyle: NexoraText.bodyStrong,
          ).copyWith(
            side: WidgetStateProperty.resolveWith<BorderSide?>(
              (states) => states.contains(WidgetState.focused)
                  ? focusRing
                  : BorderSide(color: c.borderStrong),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentCyan,
        minimumSize: const Size(48, 34),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: buttonShape,
        textStyle: NexoraText.bodyStrong,
      ).copyWith(side: focusSide),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.text2,
        minimumSize: const Size(30, 30),
      ).copyWith(side: focusSide),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: c.text2,
        selectedForegroundColor: c.onAccent,
        selectedBackgroundColor: c.accentBlue,
        side: BorderSide(color: c.borderStrong),
        textStyle: NexoraText.label,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.statusDone,
      linearTrackColor: c.border,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(c.borderStrong),
    ),
  );
}
