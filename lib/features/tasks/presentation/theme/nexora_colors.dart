import 'package:flutter/material.dart';

import 'palette.dart';

/// Semantic colours and gradients for one theme, attached to `ThemeData` as an
/// extension. Widgets read it with [NexoraColors.of]; it falls back to the
/// matching palette when a test pumps a plain `MaterialApp`.
@immutable
final class NexoraColors extends ThemeExtension<NexoraColors> {
  const NexoraColors({
    required this.brightness,
    required this.background,
    required this.panel,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.borderStrong,
    required this.text1,
    required this.text2,
    required this.textMuted,
    required this.accentBlue,
    required this.accentCyan,
    required this.accentViolet,
    required this.onAccent,
    required this.statusOpen,
    required this.statusProgress,
    required this.statusReview,
    required this.statusDone,
    required this.statusOverdue,
  });

  factory NexoraColors.fromTokens(Brightness brightness, NexoraTokenSet t) {
    return NexoraColors(
      brightness: brightness,
      background: Color(t.background),
      panel: Color(t.panel),
      surface: Color(t.surface),
      surface2: Color(t.surface2),
      border: Color(t.border),
      borderStrong: Color(t.borderStrong),
      text1: Color(t.text1),
      text2: Color(t.text2),
      textMuted: Color(t.textMuted),
      accentBlue: Color(t.accentBlue),
      accentCyan: Color(t.accentCyan),
      accentViolet: Color(t.accentViolet),
      onAccent: Color(t.onAccent),
      statusOpen: Color(t.statusOpen),
      statusProgress: Color(t.statusProgress),
      statusReview: Color(t.statusReview),
      statusDone: Color(t.statusDone),
      statusOverdue: Color(t.statusOverdue),
    );
  }

  static final NexoraColors dark = NexoraColors.fromTokens(
    Brightness.dark,
    NexoraPalette.dark,
  );
  static final NexoraColors light = NexoraColors.fromTokens(
    Brightness.light,
    NexoraPalette.light,
  );

  static NexoraColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<NexoraColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  final Brightness brightness;
  final Color background;
  final Color panel;
  final Color surface;
  final Color surface2;
  final Color border;
  final Color borderStrong;
  final Color text1;
  final Color text2;
  final Color textMuted;
  final Color accentBlue;
  final Color accentCyan;
  final Color accentViolet;
  final Color onAccent;
  final Color statusOpen;
  final Color statusProgress;
  final Color statusReview;
  final Color statusDone;
  final Color statusOverdue;

  bool get isDark => brightness == Brightness.dark;

  /// Blue to violet. Buttons, the logo mark, progress, selected chips.
  LinearGradient get brandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentBlue, accentViolet],
  );

  /// Blue to violet at low strength. The selected row and nav tile.
  LinearGradient get selectedGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      accentBlue.withValues(alpha: isDark ? 0.24 : 0.12),
      accentViolet.withValues(alpha: isDark ? 0.16 : 0.10),
    ],
  );

  /// Card surface wash: a slight two-step gradient over [surface].
  LinearGradient get cardGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.alphaBlend(accentBlue.withValues(alpha: 0.05), surface),
      surface,
    ],
  );

  /// Soft glow around focused or selected surfaces.
  Color get glow => accentBlue.withValues(alpha: isDark ? 0.24 : 0.16);

  /// A 16% tint of [color], for a badge or chip background.
  Color tint(Color color) => color.withValues(alpha: 0.16);

  @override
  NexoraColors copyWith({
    Brightness? brightness,
    Color? background,
    Color? panel,
    Color? surface,
    Color? surface2,
    Color? border,
    Color? borderStrong,
    Color? text1,
    Color? text2,
    Color? textMuted,
    Color? accentBlue,
    Color? accentCyan,
    Color? accentViolet,
    Color? onAccent,
    Color? statusOpen,
    Color? statusProgress,
    Color? statusReview,
    Color? statusDone,
    Color? statusOverdue,
  }) {
    return NexoraColors(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      panel: panel ?? this.panel,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text1: text1 ?? this.text1,
      text2: text2 ?? this.text2,
      textMuted: textMuted ?? this.textMuted,
      accentBlue: accentBlue ?? this.accentBlue,
      accentCyan: accentCyan ?? this.accentCyan,
      accentViolet: accentViolet ?? this.accentViolet,
      onAccent: onAccent ?? this.onAccent,
      statusOpen: statusOpen ?? this.statusOpen,
      statusProgress: statusProgress ?? this.statusProgress,
      statusReview: statusReview ?? this.statusReview,
      statusDone: statusDone ?? this.statusDone,
      statusOverdue: statusOverdue ?? this.statusOverdue,
    );
  }

  @override
  NexoraColors lerp(ThemeExtension<NexoraColors>? other, double t) {
    if (other is! NexoraColors) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return NexoraColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: mix(background, other.background),
      panel: mix(panel, other.panel),
      surface: mix(surface, other.surface),
      surface2: mix(surface2, other.surface2),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      text1: mix(text1, other.text1),
      text2: mix(text2, other.text2),
      textMuted: mix(textMuted, other.textMuted),
      accentBlue: mix(accentBlue, other.accentBlue),
      accentCyan: mix(accentCyan, other.accentCyan),
      accentViolet: mix(accentViolet, other.accentViolet),
      onAccent: mix(onAccent, other.onAccent),
      statusOpen: mix(statusOpen, other.statusOpen),
      statusProgress: mix(statusProgress, other.statusProgress),
      statusReview: mix(statusReview, other.statusReview),
      statusDone: mix(statusDone, other.statusDone),
      statusOverdue: mix(statusOverdue, other.statusOverdue),
    );
  }
}
