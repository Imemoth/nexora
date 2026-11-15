import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/presentation/theme/palette.dart';

/// WCAG 2.x relative luminance of an opaque ARGB colour.
double _channel(int value) {
  final s = value / 255;
  if (s <= 0.03928) {
    return s / 12.92;
  }
  return math.pow((s + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(int argb) {
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  return 0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b);
}

/// WCAG contrast ratio between two opaque colours, from 1 to 21.
double _contrast(int a, int b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

const _themes = {'dark': NexoraPalette.dark, 'light': NexoraPalette.light};

Map<String, int> _text(NexoraTokenSet t) => {
  'text1': t.text1,
  'text2': t.text2,
  'textMuted': t.textMuted,
  'accentCyan': t.accentCyan,
  'statusOpen': t.statusOpen,
  'statusProgress': t.statusProgress,
  'statusReview': t.statusReview,
  'statusDone': t.statusDone,
  'statusOverdue': t.statusOverdue,
};

Map<String, int> _grounds(NexoraTokenSet t) => {
  'background': t.background,
  'panel': t.panel,
  'surface': t.surface,
  'surface2': t.surface2,
};

void main() {
  for (final theme in _themes.entries) {
    final name = theme.key;
    final t = theme.value;

    test('$name: every text token meets 4.5:1 on all four grounds', () {
      for (final text in _text(t).entries) {
        for (final ground in _grounds(t).entries) {
          final ratio = _contrast(text.value, ground.value);
          expect(
            ratio >= 4.5,
            isTrue,
            reason:
                '${text.key} on ${ground.key} is ${ratio.toStringAsFixed(2)}',
          );
        }
      }
    });

    test('$name: borderStrong and the focus ring hold 3:1 on all grounds', () {
      for (final ground in _grounds(t).entries) {
        final strong = _contrast(t.borderStrong, ground.value);
        expect(
          strong >= 3.3,
          isTrue,
          reason: 'borderStrong on ${ground.key} is $strong',
        );
        final ring = _contrast(t.accentCyan, ground.value);
        expect(ring >= 3.0, isTrue, reason: 'focus ring on ${ground.key}');
      }
    });

    test('$name: onAccent holds 4.5:1 on every accent fill', () {
      for (final fill in {
        'accentBlue': t.accentBlue,
        'accentCyan': t.accentCyan,
        'accentViolet': t.accentViolet,
      }.entries) {
        final ratio = _contrast(t.onAccent, fill.value);
        expect(
          ratio >= 4.5,
          isTrue,
          reason: 'onAccent on ${fill.key} is ${ratio.toStringAsFixed(2)}',
        );
      }
    });

    test('$name: onSeverity holds 5.9:1 on both severity fills', () {
      for (final fill in {
        'severityWarning': t.severityWarning,
        'severityCritical': t.severityCritical,
      }.entries) {
        final ratio = _contrast(t.onSeverity, fill.value);
        expect(
          ratio >= 5.9,
          isTrue,
          reason: 'onSeverity on ${fill.key} is ${ratio.toStringAsFixed(2)}',
        );
      }
    });

    test('$name: severity tokens alias the status colours; all opaque', () {
      expect(t.severityWarning, t.statusReview);
      expect(t.severityCritical, t.statusOverdue);
      expect(t.onSeverity, t.onAccent);
      for (final value in [
        ..._text(t).values,
        ..._grounds(t).values,
        t.border,
        t.borderStrong,
        t.accentBlue,
        t.accentViolet,
        t.onAccent,
        t.severityWarning,
        t.severityCritical,
        t.onSeverity,
      ]) {
        expect(value >> 24, 0xFF);
      }
    });
  }
}
