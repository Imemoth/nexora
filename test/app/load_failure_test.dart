import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/workspace_harness.dart';

void main() {
  testWidgets(
    'a failed load tells the user, instead of showing an empty list',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = await loadedHarness(tasks: sampleTasks(), failLoad: true);

      await tester.pumpWidget(
        NexoraApp(notifier: TasksNotifier(harness.workspace)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.errorLoadFailed), findsOneWidget);
      expect(find.text(AppStrings.noTasksHere), findsNothing);
    },
  );
}
