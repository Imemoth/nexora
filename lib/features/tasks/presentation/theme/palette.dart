/// One theme's colour tokens as opaque ARGB integers. Pure Dart so the contrast
/// checks run without Flutter. Values are the authoritative `tokens.json` of the
/// Nexora Midnight design system (21 colour tokens, Dark and Light).
///
/// Grounds: [background] (canvas), [panel] (sidebar, details, list card),
/// [surface] (inputs, cards, dialogs), [surface2] (selected, hover). Text
/// tokens hold 4.5:1 on all four grounds.
final class NexoraTokenSet {
  const NexoraTokenSet({
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
    required this.severityWarning,
    required this.severityCritical,
    required this.onSeverity,
  });

  final int background;
  final int panel;
  final int surface;
  final int surface2;

  /// Decorative dividers and card edges. Not a control boundary.
  final int border;

  /// Outlined controls, selection outline and hierarchy guide lines.
  final int borderStrong;
  final int text1;
  final int text2;
  final int textMuted;

  /// The one action colour.
  final int accentBlue;

  /// Focus ring, links, due-today text and everything about reminders.
  final int accentCyan;

  /// Decorative only (project dot).
  final int accentViolet;

  /// Text and icons on an accent fill.
  final int onAccent;
  final int statusOpen;
  final int statusProgress;
  final int statusReview;
  final int statusDone;
  final int statusOverdue;

  /// Alert bar fill and sync card border for warning states.
  final int severityWarning;

  /// Alert bar fill and sync card border for critical states.
  final int severityCritical;

  /// Text and icons on a severity fill.
  final int onSeverity;
}

/// The two approved themes.
abstract final class NexoraPalette {
  static const dark = NexoraTokenSet(
    background: 0xFF060A18,
    panel: 0xFF0A1024,
    surface: 0xFF101833,
    surface2: 0xFF172044,
    border: 0xFF232C52,
    borderStrong: 0xFF6677B8,
    text1: 0xFFEAF0FF,
    text2: 0xFFB4C0E4,
    textMuted: 0xFF93A0CC,
    accentBlue: 0xFF4F8CFF,
    accentCyan: 0xFF35D6F0,
    accentViolet: 0xFF9D7CFF,
    onAccent: 0xFF050B22,
    statusOpen: 0xFF5FA2FF,
    statusProgress: 0xFFB49CFF,
    statusReview: 0xFFF5BC55,
    statusDone: 0xFF46DDA0,
    statusOverdue: 0xFFFF8294,
    // severity-warning = status-review, severity-critical = status-overdue,
    // on-severity = on-accent (same values in Dark).
    severityWarning: 0xFFF5BC55,
    severityCritical: 0xFFFF8294,
    onSeverity: 0xFF050B22,
  );

  static const light = NexoraTokenSet(
    background: 0xFFEBF1FC,
    panel: 0xFFF7F9FF,
    surface: 0xFFFFFFFF,
    surface2: 0xFFECEFFB,
    border: 0xFFD3D9EE,
    borderStrong: 0xFF7480B4,
    text1: 0xFF121A3A,
    text2: 0xFF3F4A78,
    textMuted: 0xFF58628F,
    accentBlue: 0xFF2D58E8,
    accentCyan: 0xFF08718A,
    accentViolet: 0xFF6B3CD8,
    onAccent: 0xFFFFFFFF,
    statusOpen: 0xFF1B55D6,
    statusProgress: 0xFF6535CC,
    statusReview: 0xFF8A5700,
    statusDone: 0xFF0A7648,
    statusOverdue: 0xFFC0233F,
    severityWarning: 0xFF8A5700,
    severityCritical: 0xFFC0233F,
    onSeverity: 0xFFFFFFFF,
  );
}
