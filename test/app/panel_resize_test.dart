import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/app/panel_resize.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/platform/panel_width_store.dart';

import '../support/workspace_harness.dart';

Future<TasksNotifier> _pump(
  WidgetTester tester,
  double w, {
  PanelWidthStore? store,
}) async {
  final harness = await loadedHarness(tasks: sampleTasks());
  final notifier = TasksNotifier(harness.workspace);
  tester.view.physicalSize = Size(w, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(NexoraApp(notifier: notifier, panelWidths: store));
  await tester.pumpAndSettle();
  notifier.selectTask('a');
  await tester.pumpAndSettle();
  return notifier;
}

/// A drag first spends the touch slop (about 20 px), so drags are compared with
/// a tolerance instead of an exact width.
Matcher _near(double v) => closeTo(v, 25);

/// Moves keyboard focus onto the handle with the Tab key, as a user would.
Future<void> _tabTo(WidgetTester tester, String label) async {
  for (var i = 0; i < 400; i++) {
    if (FocusManager.instance.primaryFocus?.debugLabel == label) {
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Tab never reached "$label"');
}

double _width(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(ValueKey(key))).width;

void main() {
  group('PanelLayout (limits)', () {
    test('the defaults leave the list exactly its minimum at 1100 px', () {
      final fit = PanelLayout.fit(
        PanelLayout.sidebarDefault,
        PanelLayout.detailsDefault,
        total: 1100,
      );
      expect(fit.sidebar, 248);
      expect(fit.details, 380);
      expect(1100 - fit.sidebar - fit.details, PanelLayout.centreMin);
    });

    test('nothing can grow at 1100 px, both can shrink to their minimum', () {
      expect(
        PanelLayout.details(560, total: 1100, sidebar: 248),
        380,
      ); // no room: clamped back to what fits (never below its minimum)
      expect(PanelLayout.details(100, total: 1100, sidebar: 248), 340);
      expect(PanelLayout.sidebar(100, total: 1100, details: 380), 200);
    });

    test('a wide window allows growth up to the maximum', () {
      expect(PanelLayout.details(900, total: 1920, sidebar: 248), 560);
      expect(PanelLayout.sidebar(900, total: 1920, details: 380), 360);
    });

    test('a smaller window pulls stored widths back in', () {
      final fit = PanelLayout.fit(360, 560, total: 1100);
      expect(
        fit.sidebar + fit.details + PanelLayout.centreMin,
        lessThanOrEqualTo(1100 + (360 - 200)),
      ); // never below minimums
      expect(fit.sidebar, greaterThanOrEqualTo(PanelLayout.sidebarMin));
      expect(fit.details, greaterThanOrEqualTo(PanelLayout.detailsMin));
    });
  });

  testWidgets('the defaults and the layout are unchanged', (tester) async {
    await _pump(tester, 1400);
    expect(_width(tester, 'sidebar'), 248);
    expect(_width(tester, 'details-pane'), 380);
  });

  testWidgets('dragging the details handle makes the panel wider', (
    tester,
  ) async {
    await _pump(tester, 1600);
    await tester.drag(
      find.byKey(const ValueKey('resize-details')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), _near(480));
  });

  testWidgets('dragging the sidebar handle changes only the sidebar', (
    tester,
  ) async {
    await _pump(tester, 1600);
    await tester.drag(
      find.byKey(const ValueKey('resize-sidebar')),
      const Offset(60, 0),
    );
    await tester.pumpAndSettle();
    expect(_width(tester, 'sidebar'), _near(308));
    expect(_width(tester, 'details-pane'), 380);
  });

  testWidgets('limits hold when dragging far', (tester) async {
    await _pump(tester, 1600);
    await tester.drag(
      find.byKey(const ValueKey('resize-details')),
      const Offset(-900, 0),
    );
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), PanelLayout.detailsMax);
    await tester.drag(
      find.byKey(const ValueKey('resize-details')),
      const Offset(900, 0),
    );
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), PanelLayout.detailsMin);
  });

  testWidgets('the keyboard resizes: arrows, Shift and Home', (tester) async {
    await _pump(tester, 1600);
    await _tabTo(tester, 'Resize details panel'); // reachable by Tab
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 396);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 444);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 428);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 380);
  });

  testWidgets('double click restores the default', (tester) async {
    await _pump(tester, 1600);
    await tester.drag(
      find.byKey(const ValueKey('resize-details')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    final handle = find.byKey(const ValueKey('resize-details'));
    await tester.tap(handle);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 380);
  });

  group('remembered widths', () {
    testWidgets('saved widths are restored on start', (tester) async {
      final store = InMemoryPanelWidthStore(
        const PanelWidths(sidebar: 300, details: 470),
      );
      await _pump(tester, 1600, store: store);
      expect(_width(tester, 'sidebar'), 300);
      expect(_width(tester, 'details-pane'), 470);
    });

    testWidgets('out-of-range or too wide values are kept within the limits', (
      tester,
    ) async {
      final store = InMemoryPanelWidthStore(
        const PanelWidths(sidebar: 5000, details: 20),
      );
      await _pump(tester, 1100, store: store);
      // At 1100 px nothing may grow past what leaves the list its minimum.
      expect(_width(tester, 'sidebar'), lessThanOrEqualTo(360));
      expect(_width(tester, 'details-pane'), greaterThanOrEqualTo(340));
      expect(
        1100 - _width(tester, 'sidebar') - _width(tester, 'details-pane'),
        greaterThanOrEqualTo(PanelLayout.centreMin),
      );
    });

    testWidgets('a smaller window shrinks the panels but keeps the choice', (
      tester,
    ) async {
      final store = InMemoryPanelWidthStore(
        const PanelWidths(sidebar: 300, details: 470),
      );
      await _pump(tester, 1600, store: store);
      tester.view.physicalSize = const Size(1100, 800);
      await tester.pumpAndSettle();
      expect(_width(tester, 'details-pane'), lessThan(470));
      tester.view.physicalSize = const Size(1600, 800);
      await tester.pumpAndSettle();
      expect(_width(tester, 'details-pane'), 470);
      expect(store.saves, 0, reason: 'resizing the window is not a choice');
    });

    testWidgets('a keyboard resize is saved once, after a short pause', (
      tester,
    ) async {
      final store = InMemoryPanelWidthStore();
      await _pump(tester, 1600, store: store);
      await _tabTo(tester, 'Resize details panel');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(store.saves, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.saves, 1);
      expect(store.widths?.details, 412);
      expect(store.widths?.sidebar, 248);
    });

    testWidgets('a mouse drag is saved', (tester) async {
      final store = InMemoryPanelWidthStore();
      await _pump(tester, 1600, store: store);
      await tester.drag(
        find.byKey(const ValueKey('resize-sidebar')),
        const Offset(60, 0),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.widths?.sidebar, _near(308));
    });

    testWidgets('a reset is saved and survives a restart', (tester) async {
      final store = InMemoryPanelWidthStore(
        const PanelWidths(sidebar: 300, details: 470),
      );
      await _pump(tester, 1600, store: store);
      await _tabTo(tester, 'Resize details panel');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.widths?.details, PanelLayout.detailsDefault);
      expect(store.widths?.sidebar, 300);

      // "Restart": a fresh app over the same store.
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester, 1600, store: store);
      expect(_width(tester, 'details-pane'), 380);
      expect(_width(tester, 'sidebar'), 300);
    });

    testWidgets('a change made just before the app closes is not lost', (
      tester,
    ) async {
      final store = InMemoryPanelWidthStore();
      await _pump(tester, 1600, store: store);
      await _tabTo(tester, 'Resize details panel');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      expect(store.widths?.details, 396);
    });
  });

  testWidgets('the handle is discoverable: label, value and hint', (
    tester,
  ) async {
    final h = tester.ensureSemantics();
    await _pump(tester, 1600);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('resize-details'))),
      isA<SemanticsNode>()
          .having((n) => n.label, 'label', 'Resize details panel')
          .having((n) => n.value, 'value', '380 px')
          .having((n) => n.hint, 'hint', contains('arrow keys')),
    );
    h.dispose();
  });

  testWidgets('a shrinking window pulls a widened panel back', (tester) async {
    await _pump(tester, 1800);
    await tester.drag(
      find.byKey(const ValueKey('resize-details')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 560);
    tester.view.physicalSize = const Size(1100, 800);
    await tester.pumpAndSettle();
    expect(_width(tester, 'details-pane'), 380);
    expect(_width(tester, 'sidebar'), 248);
  });

  testWidgets('the 1024 px overlay is unchanged and has no handles', (
    tester,
  ) async {
    await _pump(tester, 1024);
    expect(find.byKey(const ValueKey('details-overlay')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('details-overlay'))).width,
      380,
    );
    expect(find.byKey(const ValueKey('resize-details')), findsNothing);
    expect(find.byKey(const ValueKey('resize-sidebar')), findsNothing);
    expect(_width(tester, 'sidebar'), 248);
  });
}
