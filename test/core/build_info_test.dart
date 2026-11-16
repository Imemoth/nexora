import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/build_info.dart';

void main() {
  group('the version comes from pubspec', () {
    test('version and build number', () {
      final parsed = BuildInfo.parsePubspecVersion(
        'name: x\nversion: 1.2.3+45\nenvironment:\n  sdk: ^3.0.0\n',
      )!;
      expect(parsed.version, '1.2.3');
      expect(parsed.buildNumber, '45');
    });

    test('a version without a build number', () {
      final parsed = BuildInfo.parsePubspecVersion('version: 2.0.1\n')!;
      expect(parsed.version, '2.0.1');
      expect(parsed.buildNumber, isNull);
    });

    test('an indented or commented version line is not the version', () {
      expect(BuildInfo.parsePubspecVersion('  version: 9.9.9\n'), isNull);
      expect(BuildInfo.parsePubspecVersion('# version: 9.9.9\n'), isNull);
    });

    test('nothing parseable gives an explicit unknown, never a guess', () {
      for (final yaml in <String?>[null, '', 'version: next\n', 'name: x']) {
        final info = BuildInfo.fromSources(pubspecYaml: yaml);
        expect(info.version, BuildInfo.unknownVersion);
        expect(info.buildNumber, isNull);
      }
    });

    test('the label shows the build number only when there is one', () {
      expect(
        BuildInfo.fromSources(pubspecYaml: 'version: 1.0.0+7\n').versionLabel,
        '1.0.0+7',
      );
      expect(
        BuildInfo.fromSources(pubspecYaml: 'version: 1.0.0\n').versionLabel,
        '1.0.0',
      );
    });
  });

  group('the commit', () {
    const sha = 'a2ef9970bebeebfc7f7bdf75e75a70710b8d9761';

    test('a full CI commit shows its first seven characters', () {
      final info = BuildInfo.fromSources(
        pubspecYaml: 'version: 1.0.0\n',
        commit: sha,
        buildType: 'release',
      );
      expect(info.commit, sha);
      expect(info.shortCommit, 'a2ef997');
    });

    test('upper case and spaces are normalized', () {
      expect(BuildInfo.normalizeCommit('  A2EF997  '), 'a2ef997');
    });

    test('a dirty local build keeps its marker', () {
      final info = BuildInfo.fromSources(
        pubspecYaml: 'version: 1.0.0\n',
        commit: 'a2ef997-dirty',
      );
      expect(info.shortCommit, 'a2ef997-dirty');
    });

    test('anything that is not a commit id is unknown, never shown', () {
      for (final bad in [
        '',
        'unknown',
        'HEAD',
        'abc12', // too short
        'g2ef997', // not hex
        'a2ef997 && echo hi',
        'https://example.test/secret?token=abc',
        '${sha}00000000000000000000', // too long
      ]) {
        final info = BuildInfo.fromSources(
          pubspecYaml: 'version: 1.0.0\n',
          commit: bad,
        );
        expect(info.commit, isNull, reason: bad);
        expect(info.shortCommit, isNull, reason: bad);
      }
    });
  });

  group('the build type', () {
    BuildInfo of(String type) =>
        BuildInfo.fromSources(pubspecYaml: 'version: 1.0.0\n', buildType: type);

    test('release and development-test are recognised', () {
      expect(of('release').kind, BuildKind.release);
      expect(of('development-test').kind, BuildKind.developmentTest);
      expect(of('development-test').isDevelopmentTest, isTrue);
    });

    test('no value, or an unrecognised one, is a local build', () {
      for (final value in ['', 'prod', 'RELEASE', 'development']) {
        expect(of(value).kind, BuildKind.local, reason: value);
        expect(of(value).isDevelopmentTest, isFalse);
      }
    });
  });

  group('the CI run', () {
    test('only run-attempt digits are accepted', () {
      BuildInfo of(String run) =>
          BuildInfo.fromSources(pubspecYaml: null, runId: run);
      expect(of('1234567890-2').runId, '1234567890-2');
      expect(of('1234567890').runId, '1234567890');
      expect(of('abc').runId, isNull);
      expect(of('1; rm -rf').runId, isNull);
      expect(of('').runId, isNull);
    });
  });

  test('the report holds only the build identity', () {
    final info = BuildInfo.fromSources(
      pubspecYaml: 'version: 1.0.0+3\n',
      commit: 'a2ef9970bebeebfc7f7bdf75e75a70710b8d9761',
      buildType: 'development-test',
      runId: '99-1',
      syncEnabled: true,
    );
    expect(
      info.toReport(
        appName: 'Nexora',
        buildTypeLabel: 'DEVELOPMENT TEST',
        unknownCommitLabel: 'unknown',
        syncLabel: 'On',
      ),
      'Nexora 1.0.0+3\n'
      'Commit: a2ef9970bebeebfc7f7bdf75e75a70710b8d9761\n'
      'Build: DEVELOPMENT TEST\n'
      'Synchronization: On\n'
      'CI run: 99-1',
    );
  });

  test('an unknown build reports unknown, not a commit', () {
    expect(
      BuildInfo.unknown.toReport(
        appName: 'Nexora',
        buildTypeLabel: 'Local build',
        unknownCommitLabel: 'unknown',
        syncLabel: 'Off',
      ),
      'Nexora unknown\nCommit: unknown\nBuild: Local build\nSynchronization: Off',
    );
  });
}
