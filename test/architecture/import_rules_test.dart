import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importPattern = RegExp(r"^import '([^']+)'", multiLine: true);

/// Pure layers: Dart core libraries, this package, and relative imports only.
const _pureLayerDirs = [
  'lib/core',
  'lib/features/tasks/domain',
  'lib/features/tasks/application',
];

/// Libraries no layer may import in Phase 1.
const _forbiddenEverywhere = [
  'package:sqlite',
  'package:supabase',
  'package:http',
];

List<File> _dartFiles(String dir) {
  final root = Directory(dir);
  final files = <File>[];
  if (!root.existsSync()) {
    return files;
  }
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }
  return files;
}

List<String> _importsOf(File file) {
  final source = file.readAsStringSync();
  return [
    for (final match in _importPattern.allMatches(source)) match.group(1)!,
  ];
}

void main() {
  test('pure layers import only allowed libraries', () {
    for (final dir in _pureLayerDirs) {
      for (final file in _dartFiles(dir)) {
        for (final uri in _importsOf(file)) {
          final isPackage = uri.startsWith('package:');
          final allowed = !isPackage || uri.startsWith('package:nexora/');
          expect(allowed, isTrue, reason: '${file.path} imports $uri');
          expect(uri, isNot('dart:ui'), reason: file.path);
          expect(uri, isNot('dart:io'), reason: file.path);
        }
      }
    }
  });

  test('no Flutter import in core, domain or application layers', () {
    for (final dir in [..._pureLayerDirs, 'lib/features/tasks/application']) {
      for (final file in _dartFiles(dir)) {
        for (final uri in _importsOf(file)) {
          expect(
            uri.startsWith('package:flutter'),
            isFalse,
            reason: '${file.path} imports $uri',
          );
        }
      }
    }
  });

  test('no persistence or network package anywhere in lib', () {
    for (final file in _dartFiles('lib')) {
      for (final uri in _importsOf(file)) {
        for (final forbidden in _forbiddenEverywhere) {
          expect(
            uri.startsWith(forbidden),
            isFalse,
            reason: '${file.path} imports $uri',
          );
        }
      }
    }
  });
}
