import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/sync_panel.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

void main() {
  Future<StreamController<SyncStatus>> pump(
    WidgetTester tester,
    SyncStatus initial,
    Future<void> Function() syncNow,
  ) async {
    final controller = StreamController<SyncStatus>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusBar(
            panel: SyncPanel(
              initial: initial,
              statuses: controller.stream,
              syncNow: syncNow,
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('shows the state in words and runs a manual sync', (
    tester,
  ) async {
    var runs = 0;
    final controller = await pump(
      tester,
      const SyncStatus(phase: SyncPhase.idle),
      () async => runs++,
    );
    expect(find.text(AppStrings.syncUpToDate), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sync-now')));
    expect(runs, 1);

    controller.add(const SyncStatus(phase: SyncPhase.idle, openConflicts: 2));
    await tester.pump();
    expect(find.text(AppStrings.syncConflicts(2)), findsOneWidget);

    controller.add(const SyncStatus(phase: SyncPhase.authRequired, pending: 3));
    await tester.pump();
    expect(find.text(AppStrings.syncSignInNeeded), findsOneWidget);
  });

  testWidgets('the action is disabled while synchronizing', (tester) async {
    var runs = 0;
    await pump(
      tester,
      const SyncStatus(phase: SyncPhase.syncing),
      () async => runs++,
    );
    await tester.tap(find.byKey(const ValueKey('sync-now')));
    expect(runs, 0);
    expect(find.text(AppStrings.syncing), findsOneWidget);
  });

  test('every phase has a text, and pending, rejected and conflicts are told apart', () {
    for (final phase in SyncPhase.values) {
      expect(SyncStatusBar.describe(SyncStatus(phase: phase)), isNotEmpty);
    }
    expect(
      SyncStatusBar.describe(const SyncStatus(phase: SyncPhase.idle, rejected: 1)),
      AppStrings.syncRejected(1),
    );
    expect(
      SyncStatusBar.describe(const SyncStatus(phase: SyncPhase.idle, pending: 4)),
      AppStrings.syncPending(4),
    );
  });
}
