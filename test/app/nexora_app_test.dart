import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/workspace_harness.dart';

// Phase 0 assertion replaced in Phase 1 Task 3: the placeholder text
// "Offline ready" is replaced by the three-pane shell. Old assertion:
//   expect(find.text('Offline ready'), findsOneWidget);
void main() {
  testWidgets('app boots without network and shows the three-pane shell', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    final demo = buildDemoData(testToday);
    final harness = await loadedHarness(
      tasks: demo.tasks,
      projects: demo.projects,
    );
    await tester.pumpWidget(
      NexoraApp(notifier: TasksNotifier(harness.workspace)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nexora'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar')), findsOneWidget);
    expect(errors, isEmpty);
  });
}
