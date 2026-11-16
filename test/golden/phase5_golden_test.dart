import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_panel.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/app/sync_panel.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/settings_store.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/features/tasks/presentation/theme/theme_controller.dart';

import '../support/workspace_harness.dart';

/// Phase 5 baselines: workspace, dashboard, details overlay, gate dialog and
/// alert bar, at 1366x768 and 1024x768, in Dark and Light. Generated only on
/// the pinned Windows CI runner (decision 9). Demo data is fixed to
/// [testToday], so the output is deterministic.
const _sizes = {'1366x768': Size(1366, 768), '1024x768': Size(1024, 768)};
const _themes = {'dark': ThemePreference.dark, 'light': ThemePreference.light};

Future<TasksNotifier> _pump(
  WidgetTester tester, {
  required Size size,
  required ThemePreference theme,
  SyncPanel? sync,
  AccountPanel? account,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final demo = buildDemoData(testToday);
  final harness = await loadedHarness(
    tasks: demo.tasks,
    projects: demo.projects,
  );
  final notifier = TasksNotifier(harness.workspace);
  await tester.pumpWidget(
    NexoraApp(
      notifier: notifier,
      themeController: ThemeController(
        InMemorySettingsStore(theme),
        initial: theme,
      ),
      syncPanel: sync,
      accountPanel: account,
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  for (final size in _sizes.entries) {
    for (final theme in _themes.entries) {
      final tag = '${size.key}_${theme.key}';

      testWidgets('workspace $tag', (tester) async {
        final notifier = await _pump(
          tester,
          size: size.value,
          theme: theme.value,
        );
        notifier.selectTask('home-groceries');
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phase5/workspace_$tag.png'),
        );
      });

      testWidgets('dashboard $tag', (tester) async {
        final notifier = await _pump(
          tester,
          size: size.value,
          theme: theme.value,
        );
        notifier.selectDashboard();
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phase5/dashboard_$tag.png'),
        );
      });

      testWidgets('details $tag', (tester) async {
        final notifier = await _pump(
          tester,
          size: size.value,
          theme: theme.value,
        );
        notifier.selectTask('home-groceries');
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phase5/details_$tag.png'),
        );
      });

      testWidgets('gate dialog $tag', (tester) async {
        final notifier = await _pump(
          tester,
          size: size.value,
          theme: theme.value,
        );
        notifier.selectTask('home-groceries');
        notifier.editDraft(title: 'Plan weekend groceries and more');
        await tester.pumpAndSettle();
        notifier.selectTask('home-utility');
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phase5/gate_$tag.png'),
        );
      });

      testWidgets('alert bar $tag', (tester) async {
        final controller = StreamController<SyncStatus>.broadcast();
        addTearDown(controller.close);
        await _pump(
          tester,
          size: size.value,
          theme: theme.value,
          sync: SyncPanel(
            initial: const SyncStatus(phase: SyncPhase.idle, openConflicts: 2),
            statuses: controller.stream,
            syncNow: () async {},
          ),
          account: AccountPanel(
            initial: const AccountView(
              phase: AccountPhase.signedIn,
              email: 'me@example.test',
            ),
            views: const Stream<AccountView>.empty(),
            signIn: (e, p) async => SignInOutcome.success,
            signOut: () async {},
          ),
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/phase5/alert_$tag.png'),
        );
      });
    }
  }
}
