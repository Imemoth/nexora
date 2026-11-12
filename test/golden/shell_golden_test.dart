import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/workspace_harness.dart';

/// Golden baselines are generated only on the pinned Windows CI runner (decision
/// 9). Demo data is fixed to [testToday], so the output is deterministic.
Future<void> _pump(WidgetTester tester, Harness harness) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('All view with a selected task matches the golden', (
    tester,
  ) async {
    final demo = buildDemoData(testToday);
    final harness = await loadedHarness(
      tasks: demo.tasks,
      projects: demo.projects,
    );
    await _pump(tester, harness);
    await tester.tap(find.byKey(const ValueKey('row-home-groceries')));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/all_view_selected.png'),
    );
  });

  testWidgets('empty state matches the golden', (tester) async {
    final harness = await loadedHarness(
      tasks: const [],
      projects: testProjects,
    );
    await _pump(tester, harness);

    expect(find.text(AppStrings.noTasksHere), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/empty_state.png'),
    );
  });
}
