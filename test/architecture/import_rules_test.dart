import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _importPattern = RegExp(r"^import '([^']+)'", multiLine: true);

/// Pure layers: Dart core libraries, this package, and relative imports only.
const _pureLayerDirs = [
  'lib/core',
  'lib/features/tasks/domain',
  'lib/features/tasks/application',
];

/// The local persistence layer. It is pure Dart: no Flutter, and it may use the
/// SQLite package and `dart:io`. Only this layer may import SQLite.
const _dataLayerDir = 'lib/features/tasks/data';

/// Code that must never reach the database directly. The UI depends on
/// `TaskWorkspace` and the repository abstraction, not on SQLite or the data layer.
const _uiDirs = ['lib/features/tasks/presentation', 'lib/app'];

/// Libraries no layer may import. The Supabase and network packages are not
/// approved in any slice so far.
const _forbiddenEverywhere = ['package:supabase', 'package:http'];

/// The SQLite package. Allowed only in the data layer.
const _sqlitePackage = 'package:sqlite3';

String _normalize(String path) => path.replaceAll('\\', '/');

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

  test('no Flutter import in core, domain, application or data layers', () {
    for (final dir in [..._pureLayerDirs, _dataLayerDir]) {
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

  test('no Supabase or network package anywhere in lib', () {
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

  test('SQLite is imported only by the data layer', () {
    for (final file in _dartFiles('lib')) {
      if (_normalize(file.path).contains('$_dataLayerDir/')) {
        continue;
      }
      for (final uri in _importsOf(file)) {
        expect(
          uri.startsWith(_sqlitePackage),
          isFalse,
          reason: '${file.path} imports $uri outside the data layer',
        );
      }
    }
  });

  test('the UI never imports the data layer or SQLite', () {
    for (final dir in _uiDirs) {
      for (final file in _dartFiles(dir)) {
        for (final uri in _importsOf(file)) {
          final reachesData =
              uri.contains('features/tasks/data/') ||
              uri.startsWith(_sqlitePackage);
          expect(
            reachesData,
            isFalse,
            reason:
                '${file.path} imports $uri; the UI must use the repository abstraction',
          );
        }
      }
    }
  });
}
