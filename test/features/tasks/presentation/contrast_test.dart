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

Map<String, int> _textTokens(NexoraTokenSet t) => {
  'text1': t.text1,
  'text2': t.text2,
  'textMuted': t.textMuted,
  'accentBlue': t.accentBlue,
  'accentCyan': t.accentCyan,
  'accentViolet': t.accentViolet,
  'statusOpen': t.statusOpen,
  'statusProgress': t.statusProgress,
  'statusReview': t.statusReview,
  'statusDone': t.statusDone,
  'statusOverdue': t.statusOverdue,
};

Map<String, int> _surfaces(NexoraTokenSet t) => {
  'background': t.background,
  'panel': t.panel,
  'surface': t.surface,
  'surface2': t.surface2,
};

final _themes = {'dark': NexoraPalette.dark, 'light': NexoraPalette.light};

void main() {
  for (final entry in _themes.entries) {
    final name = entry.key;
    final tokens = entry.value;

    test('$name: every text token meets 4.5:1 on every surface', () {
      for (final text in _textTokens(tokens).entries) {
        for (final surface in _surfaces(tokens).entries) {
          final ratio = _contrast(text.value, surface.value);
          expect(
            ratio >= 4.5,
            isTrue,
            reason:
                '$name ${text.key} on ${surface.key} is ${ratio.toStringAsFixed(2)}',
          );
        }
      }
    });

    test('$name: text on a filled accent meets 4.5:1', () {
      for (final fill in [tokens.accentBlue, tokens.accentViolet]) {
        final ratio = _contrast(tokens.onAccent, fill);
        expect(ratio >= 4.5, isTrue, reason: '$name onAccent is $ratio');
      }
    });

    test('$name: outlined control borders and the focus ring meet 3:1', () {
      for (final surface in _surfaces(tokens).entries) {
        final border = _contrast(tokens.borderStrong, surface.value);
        expect(
          border >= 3.0,
          isTrue,
          reason: '$name borderStrong on ${surface.key} is $border',
        );
        final ring = _contrast(tokens.accentCyan, surface.value);
        expect(
          ring >= 3.0,
          isTrue,
          reason: '$name accentCyan on ${surface.key} is $ring',
        );
      }
    });

    test('$name: the palette is opaque', () {
      final all = [
        ..._textTokens(tokens).values,
        ..._surfaces(tokens).values,
        tokens.border,
        tokens.borderStrong,
        tokens.onAccent,
      ];
      for (final value in all) {
        expect(value >> 24, 0xFF);
      }
    });
  }
}
