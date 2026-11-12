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

const _textTokens = {
  'text1': NexoraPalette.text1,
  'text2': NexoraPalette.text2,
  'textMuted': NexoraPalette.textMuted,
  'primary': NexoraPalette.primary,
  'positive': NexoraPalette.positive,
  'negative': NexoraPalette.negative,
  'warning': NexoraPalette.warning,
};

const _surfaceTokens = {
  'background': NexoraPalette.background,
  'surface': NexoraPalette.surface,
  'surface2': NexoraPalette.surface2,
};

void main() {
  test('every text token meets 4.5:1 on every surface (normal text)', () {
    for (final text in _textTokens.entries) {
      for (final surface in _surfaceTokens.entries) {
        final ratio = _contrast(text.value, surface.value);
        expect(
          ratio >= 4.5,
          isTrue,
          reason: '${text.key} on ${surface.key} is ${ratio.toStringAsFixed(2)}',
        );
      }
    }
  });

  test('every text token meets 3:1 on every surface (large text)', () {
    for (final text in _textTokens.entries) {
      for (final surface in _surfaceTokens.entries) {
        final ratio = _contrast(text.value, surface.value);
        expect(
          ratio >= 3.0,
          isTrue,
          reason: '${text.key} on ${surface.key} is ${ratio.toStringAsFixed(2)}',
        );
      }
    }
  });

  test('the palette is opaque', () {
    for (final value in [
      ..._textTokens.values,
      ..._surfaceTokens.values,
      NexoraPalette.border,
    ]) {
      expect(value >> 24, 0xFF);
    }
  });
}
