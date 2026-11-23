import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/app/sync_card.dart';
import 'package:nexora/app/sync_panel.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/platform/panel_width_store.dart';

import '../support/workspace_harness.dart';

/// Narrow sidebar (200 px is its minimum, 150 % scaling makes that common):
/// the sync status and the project names stay understandable.
void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    double width,
    SyncStatus status,
  ) async {
    final controller = StreamController<SyncStatus>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SyncCard(
                syncPanel: SyncPanel(
                  initial: status,
                  statuses: controller.stream,
                  syncNow: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const waiting = SyncStatus(phase: SyncPhase.idle, pending: 3);

  testWidgets('wide enough: title and action share a line', (tester) async {
    // The test font is wider than the real one, so "enough" is generous.
    await pumpCard(tester, 600, waiting);
    final title = tester.getRect(find.byKey(const ValueKey('sync-title')));
    final action = tester.getRect(find.byKey(const ValueKey('sync-now')));
    expect((title.center.dy - action.center.dy).abs(), lessThan(8));
  });

  for (final width in [176.0, 140.0]) {
    testWidgets('${width.toInt()} px: the title keeps its width and the action '
        'moves below it', (tester) async {
      await pumpCard(tester, width, waiting);
      final card = tester.getRect(
        find.byKey(const ValueKey('sync-status-bar')),
      );
      final title = tester.getRect(find.byKey(const ValueKey('sync-title')));
      final action = tester.getRect(find.byKey(const ValueKey('sync-now')));
      expect(title.width, greaterThan(70));
      expect(action.top, greaterThanOrEqualTo(title.bottom - 1));
      expect(action.right, lessThanOrEqualTo(card.right));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a long project name is cut in the sidebar but reachable', (
    tester,
  ) async {
    const long = 'Regional finance and procurement programme 2027';
    final h = await loadedHarness(
      tasks: sampleTasks(),
      projects: const [Project(id: 'p1', name: long, position: 0)],
    );
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NexoraApp(
        notifier: TasksNotifier(h.workspace),
        // The narrowest sidebar the user can choose.
        panelWidths: InMemoryPanelWidthStore(
          const PanelWidths(sidebar: 200, details: 380),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byKey(const ValueKey('nav-project-p1'));
    final label = find.descendant(of: tile, matching: find.text(long));
    expect(label, findsOneWidget);
    expect(
      tester.getRect(label).right,
      lessThanOrEqualTo(tester.getRect(tile).right),
    );
    expect(
      tester
          .widget<Tooltip>(
            find.descendant(of: tile, matching: find.byType(Tooltip)),
          )
          .message,
      long,
      reason: 'hovering shows the whole name',
    );
    expect(tester.takeException(), isNull);
  });
}
