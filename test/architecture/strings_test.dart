import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Visible-text literals that must live in `strings/app_strings.dart`.
const _literalPatterns = [
  "Text('",
  "hintText: '",
  "labelText: '",
  "tooltip: '",
  "title: '",
];

/// Directories that contain user-facing widget code.
const _presentationRoots = ['lib/app', 'lib/features'];

Iterable<File> _presentationFiles() sync* {
  for (final root in _presentationRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) {
      continue;
    }
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalized = entity.path.replaceAll('\\', '/');
      if (!normalized.contains('/presentation/') &&
          !normalized.startsWith('lib/app/')) {
        continue;
      }
      if (normalized.contains('/presentation/strings/')) {
        continue;
      }
      yield entity;
    }
  }
}

void main() {
  test('no visible-text literals outside presentation strings', () {
    final violations = <String>[];
    for (final file in _presentationFiles()) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final pattern in _literalPatterns) {
          if (lines[i].contains(pattern)) {
            violations.add('${file.path}:${i + 1} contains $pattern');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
