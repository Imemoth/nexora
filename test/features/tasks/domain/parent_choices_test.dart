import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/parent_choices.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/task_fixtures.dart';

void main() {
  test('offers the tasks of the project in tree order with their depth', () {
    final choices = subtaskParentChoices(
      projectId: 'p1',
      tasks: [
        makeTask(id: 'b', title: 'B', position: 1),
        makeTask(id: 'a', title: 'A', position: 0),
        makeTask(id: 'a1', title: 'A1', parentId: 'a'),
        makeTask(id: 'a1x', title: 'A1x', parentId: 'a1'),
      ],
    );
    expect(choices.map((c) => c.task.id), ['a', 'a1', 'a1x', 'b']);
    expect(choices.map((c) => c.depth), [0, 1, 2, 0]);
  });

  test(
    'tasks of another project are never offered (no cross-project parent)',
    () {
      final choices = subtaskParentChoices(
        projectId: 'p1',
        tasks: [
          makeTask(id: 'mine', title: 'Mine'),
          makeTask(id: 'other', projectId: 'p2', title: 'Other'),
        ],
      );
      expect(choices.map((c) => c.task.id), ['mine']);
    },
  );

  test('archived tasks are left out, their open children are kept', () {
    final choices = subtaskParentChoices(
      projectId: 'p1',
      tasks: [
        makeTask(id: 'old', title: 'Old', status: TaskStatus.archived),
        makeTask(id: 'kid', title: 'Kid', parentId: 'old'),
      ],
    );
    expect(choices.map((c) => c.task.id), ['kid']);
    expect(choices.single.ancestors, ['Old']);
  });

  test('same-named tasks are told apart by their ancestry', () {
    final choices = subtaskParentChoices(
      projectId: 'p1',
      tasks: [
        makeTask(id: 'x', title: 'Plan', position: 0),
        makeTask(id: 'y', title: 'Plan', position: 1),
        makeTask(id: 'x1', title: 'Budget', parentId: 'x'),
        makeTask(id: 'y1', title: 'Budget', parentId: 'y'),
      ],
    );
    final budgets = choices.where((c) => c.task.title == 'Budget').toList();
    expect(budgets, hasLength(2));
    expect(budgets.map((c) => c.task.id), ['x1', 'y1']);
    // Same title, same ancestor titles: the ids differ, the order is stable.
    expect(choices.where((c) => c.task.title == 'Plan').map((c) => c.task.id), [
      'x',
      'y',
    ]);
  });

  test('stored data that loops cannot hang the ancestry walk', () {
    final choices = subtaskParentChoices(
      projectId: 'p1',
      tasks: [
        makeTask(id: 'a', title: 'A', parentId: 'b'),
        makeTask(id: 'b', title: 'B', parentId: 'a'),
      ],
    );
    expect(choices, isNotNull); // terminates
  });
}
