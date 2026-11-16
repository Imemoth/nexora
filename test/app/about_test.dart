import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/build_info_loader.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/core/build_info.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/workspace_harness.dart';

const _sha = 'a2ef9970bebeebfc7f7bdf75e75a70710b8d9761';

Future<void> _openAbout(WidgetTester tester, BuildInfo info) async {
  final harness = await loadedHarness(tasks: sampleTasks());
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(
      notifier: TasksNotifier(harness.workspace),
      themeController: ThemeController(InMemorySettingsStore()),
      buildInfo: info,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('account-row')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('menu-about')));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<SelectableText>(find.byKey(ValueKey(key))).data!;

void main() {
  testWidgets('About is in the account menu and shows version and commit', (
    tester,
  ) async {
    await _openAbout(
      tester,
      BuildInfo.fromSources(
        pubspecYaml: 'version: 1.4.2+9\n',
        commit: _sha,
        buildType: 'release',
        runId: '555-1',
      ),
    );
    expect(find.byKey(const ValueKey('about-dialog')), findsOneWidget);
    expect(_text(tester, 'about-version'), '1.4.2+9');
    expect(_text(tester, 'about-commit'), 'a2ef997');
    expect(_text(tester, 'about-build-type'), AppStrings.buildTypeRelease);
    expect(_text(tester, 'about-run'), '555-1');
    expect(find.byKey(const ValueKey('about-note')), findsNothing);
  });

  testWidgets('a DEVELOPMENT TEST build is clearly marked', (tester) async {
    await _openAbout(
      tester,
      BuildInfo.fromSources(
        pubspecYaml: 'version: 1.0.0+1\n',
        commit: _sha,
        buildType: 'development-test',
      ),
    );
    expect(
      _text(tester, 'about-build-type'),
      AppStrings.buildTypeDevelopmentTest,
    );
    expect(find.text(AppStrings.aboutDevelopmentNote), findsOneWidget);
    // Distinct from the normal build's wording.
    expect(find.text(AppStrings.buildTypeRelease), findsNothing);
  });

  testWidgets('a synchronization build says so', (tester) async {
    await _openAbout(
      tester,
      BuildInfo.fromSources(
        pubspecYaml: 'version: 1.1.0+2\n',
        commit: _sha,
        buildType: 'development-test',
        syncEnabled: true,
      ),
    );
    expect(_text(tester, 'about-sync'), AppStrings.syncOn);
    expect(
      _text(tester, 'about-build-type'),
      AppStrings.buildTypeDevelopmentTest,
    );
  });

  testWidgets('a local-only release build says that', (tester) async {
    await _openAbout(
      tester,
      BuildInfo.fromSources(
        pubspecYaml: 'version: 1.1.0+2\n',
        commit: _sha,
        buildType: 'release',
      ),
    );
    expect(_text(tester, 'about-sync'), AppStrings.syncOff);
    expect(_text(tester, 'about-build-type'), AppStrings.buildTypeRelease);
  });

  testWidgets('a local build has an explicit unknown commit, never a guess', (
    tester,
  ) async {
    await _openAbout(
      tester,
      BuildInfo.fromSources(pubspecYaml: 'version: 1.0.0+1\n'),
    );
    expect(_text(tester, 'about-commit'), AppStrings.commitUnknown);
    expect(_text(tester, 'about-build-type'), AppStrings.buildTypeLocal);
    expect(find.text(AppStrings.aboutLocalNote), findsOneWidget);
    expect(find.byKey(const ValueKey('about-run')), findsNothing);
  });

  testWidgets('missing metadata altogether still opens, all unknown', (
    tester,
  ) async {
    await _openAbout(tester, BuildInfo.unknown);
    expect(_text(tester, 'about-version'), BuildInfo.unknownVersion);
    expect(_text(tester, 'about-commit'), AppStrings.commitUnknown);
    expect(tester.takeException(), isNull);
  });

  testWidgets('without any build info passed the app shows an unknown build', (
    tester,
  ) async {
    final harness = await loadedHarness(tasks: sampleTasks());
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NexoraApp(
        notifier: TasksNotifier(harness.workspace),
        themeController: ThemeController(InMemorySettingsStore()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account-row')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-about')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'about-commit'), AppStrings.commitUnknown);
  });

  testWidgets('Copy details puts the plain identity on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _openAbout(
      tester,
      BuildInfo.fromSources(
        pubspecYaml: 'version: 1.0.0+1\n',
        commit: _sha,
        buildType: 'development-test',
        runId: '7-1',
        syncEnabled: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('about-copy')));
    await tester.pumpAndSettle();
    expect(
      copied,
      'Nexora 1.0.0+1\nCommit: $_sha\nBuild: DEVELOPMENT TEST\nSynchronization: ${AppStrings.syncOn}\nCI run: 7-1',
    );
    expect(find.text(AppStrings.aboutCopied), findsOneWidget);
  });

  testWidgets('Close dismisses the dialog', (tester) async {
    await _openAbout(tester, BuildInfo.unknown);
    await tester.tap(find.byKey(const ValueKey('about-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('about-dialog')), findsNothing);
  });

  group('the loader: the version has one source', () {
    testWidgets('the bundled pubspec gives the version in pubspec.yaml', (
      tester,
    ) async {
      // Asset loading is real I/O: it must run outside the fake-async zone.
      final info = (await tester.runAsync(
        () => loadBuildInfo(commit: '', buildType: '', runId: ''),
      ))!;
      final line = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
      expect(info.versionLabel, line);
      expect(info.commit, isNull); // nothing was defined: no commit is shown
      expect(info.kind, BuildKind.local);
    });

    testWidgets('build-time values are passed through, validated', (
      tester,
    ) async {
      final info = (await tester.runAsync(
        () => loadBuildInfo(commit: _sha, buildType: 'release', runId: '12-3'),
      ))!;
      expect(info.shortCommit, 'a2ef997');
      expect(info.kind, BuildKind.release);
      expect(info.runId, '12-3');
    });

    testWidgets('a bundle that cannot be read leaves the version unknown', (
      tester,
    ) async {
      final info = await loadBuildInfo(bundle: _BrokenBundle());
      expect(info.version, BuildInfo.unknownVersion);
    });
  });
}

final class _BrokenBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => throw FlutterError('no asset');
}
