import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../support/task_fixtures.dart';
import '../support/workspace_harness.dart';

/// Creating a subtask: the current task is the preselected parent, another
/// valid parent of the same project can be chosen, and nothing crosses projects.
Future<Harness> _pump(WidgetTester tester) async {
  final harness = await loadedHarness(
    tasks: [
      makeTask(id: 'plan1', title: 'Plan', position: 0),
      makeTask(id: 'plan2', title: 'Plan', position: 1),
      makeTask(id: 'budget', title: 'Budget', parentId: 'plan2'),
      makeTask(id: 'old', title: 'Archived one', status: TaskStatus.archived),
      makeTask(id: 'work', projectId: 'p2', title: 'Work task'),
    ],
  );
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    NexoraApp(notifier: TasksNotifier(harness.workspace)),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _openDialogFrom(WidgetTester tester, String rowId) async {
  await tester.tap(find.byKey(ValueKey('row-$rowId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('add-subtask')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the current task is preselected as the parent', (tester) async {
    final h = await _pump(tester);
    await _openDialogFrom(tester, 'plan1');
    final dropdown = tester.widget<DropdownButton<String>>(
      find.byKey(const ValueKey('create-parent')),
    );
    expect(dropdown.value, 'plan1');

    await tester.enterText(find.byKey(const ValueKey('create-title')), 'Sub');
    await tester.tap(find.byKey(const ValueKey('create-submit')));
    await tester.pumpAndSettle();

    expect(h.workspace.state.tasks['new-1']!.parentId, 'plan1');
    expect(h.workspace.state.tasks['new-1']!.projectId, 'p1');
  });

  testWidgets('another valid parent of the same project can be chosen', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _openDialogFrom(tester, 'plan1');
    await tester.tap(find.byKey(const ValueKey('create-parent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-parent-budget')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('create-title')), 'Deep');
    await tester.tap(find.byKey(const ValueKey('create-submit')));
    await tester.pumpAndSettle();

    final created = h.workspace.state.tasks['new-1']!;
    expect(created.parentId, 'budget');
    expect(created.projectId, 'p1');
    expect(h.workspace.state.expandedTaskIds, contains('budget'));
  });

  testWidgets('same-named tasks show their ancestry; the project is context', (
    tester,
  ) async {
    await _pump(tester);
    await _openDialogFrom(tester, 'plan1');
    expect(find.text('${AppStrings.fieldProject}: Home'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-parent')));
    await tester.pumpAndSettle();
    // Both "Plan" tasks are listed, and the child names its parent.
    expect(find.text('Plan'), findsWidgets);
    expect(find.text('Budget'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('create-parent-budget')),
        matching: find.text('Plan'),
      ),
      findsOneWidget,
    ); // the ancestry line under "Budget"
  });

  testWidgets('no task of another project and no archived task is offered', (
    tester,
  ) async {
    await _pump(tester);
    await _openDialogFrom(tester, 'plan1');
    await tester.tap(find.byKey(const ValueKey('create-parent')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-parent-work')), findsNothing);
    expect(find.byKey(const ValueKey('create-parent-old')), findsNothing);
    expect(find.byKey(const ValueKey('create-parent-plan2')), findsWidgets);
  });

  testWidgets('a new root task is unaffected: it has a project, no parent', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('new-task')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-parent')), findsNothing);
    expect(find.byKey(const ValueKey('create-project')), findsOneWidget);
  });
}
