import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/nav_selection.dart';
import 'package:nexora/features/tasks/application/workspace_state.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';

import '../../../support/workspace_harness.dart';

void main() {
  group('TasksNotifier', () {
    test('forwards navigation intents to the workspace', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final notifier = TasksNotifier(h.workspace);

      notifier.selectView(SmartView.today);
      expect(
        (notifier.state.selection as SmartViewSelection).view,
        SmartView.today,
      );

      notifier.selectProject('p1');
      expect((notifier.state.selection as ProjectSelection).projectId, 'p1');

      notifier.selectTask('a');
      expect(notifier.state.selectedTaskId, 'a');

      notifier.search('alp');
      expect(notifier.state.searchQuery, 'alp');

      notifier.sort(TaskSort.title);
      expect(notifier.state.sort, TaskSort.title);

      notifier.toggleExpanded('parent');
      expect(notifier.state.expandedTaskIds, contains('parent'));

      notifier.dispose();
    });

    test('notifies listeners once for every workspace emission', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final notifier = TasksNotifier(h.workspace);
      final emissions = <WorkspaceState>[];
      final subscription = h.workspace.states.listen(emissions.add);
      var notifications = 0;
      notifier.addListener(() => notifications++);

      notifier.selectTask('a');
      notifier.search('x');
      await Future<void>.delayed(Duration.zero);

      expect(emissions, hasLength(2));
      expect(notifications, 2);

      await subscription.cancel();
      notifier.dispose();
    });

    test('stops listening to the workspace after dispose', () async {
      final h = await loadedHarness(tasks: sampleTasks());
      final notifier = TasksNotifier(h.workspace);
      notifier.dispose();

      h.workspace.requestSelectTask('a');
      await Future<void>.delayed(Duration.zero);

      expect(h.workspace.state.selectedTaskId, 'a');
    });
  });
}
