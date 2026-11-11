import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/result.dart';
import 'package:nexora/features/tasks/domain/task_tree_rules.dart';

import '../../../support/task_fixtures.dart';

void main() {
  group('validateParentChange', () {
    test('accepts moving a task under a sibling in the same project', () {
      final tasks = byId([
        makeTask(id: 'a'),
        makeTask(id: 'b'),
      ]);

      final result = validateParentChange(
        tasks: tasks,
        taskId: 'b',
        newParentId: 'a',
      );

      expect(result, isA<Ok<void, ParentChangeError>>());
    });

    test('accepts moving a task to the root', () {
      final tasks = byId([
        makeTask(id: 'a', parentId: 'b'),
        makeTask(id: 'b'),
      ]);

      final result = validateParentChange(
        tasks: tasks,
        taskId: 'a',
        newParentId: null,
      );

      expect(result, isA<Ok<void, ParentChangeError>>());
    });

    test('rejects a task that is its own parent', () {
      final tasks = byId([makeTask(id: 'a')]);

      final error = errValue(
        validateParentChange(tasks: tasks, taskId: 'a', newParentId: 'a'),
      );

      expect(error, ParentChangeError.selfParent);
    });

    test('rejects a parent that does not exist', () {
      final tasks = byId([makeTask(id: 'a')]);

      final error = errValue(
        validateParentChange(tasks: tasks, taskId: 'a', newParentId: 'ghost'),
      );

      expect(error, ParentChangeError.missingParent);
    });

    test('rejects a task that does not exist', () {
      final tasks = byId([makeTask(id: 'a')]);

      final error = errValue(
        validateParentChange(tasks: tasks, taskId: 'ghost', newParentId: 'a'),
      );

      expect(error, ParentChangeError.missingTask);
    });

    test('rejects a parent in another project', () {
      final tasks = byId([
        makeTask(id: 'a', projectId: 'p1'),
        makeTask(id: 'b', projectId: 'p2'),
      ]);

      final error = errValue(
        validateParentChange(tasks: tasks, taskId: 'b', newParentId: 'a'),
      );

      expect(error, ParentChangeError.crossProject);
    });

    test('rejects a direct cycle through the proposed parent chain', () {
      // A is root, B under A, C under B. Moving A under C creates A->C->B->A.
      final tasks = byId([
        makeTask(id: 'a'),
        makeTask(id: 'b', parentId: 'a'),
        makeTask(id: 'c', parentId: 'b'),
      ]);

      final error = errValue(
        validateParentChange(tasks: tasks, taskId: 'a', newParentId: 'c'),
      );

      expect(error, ParentChangeError.cycle);
    });

    test('rejects a longer cycle', () {
      final tasks = byId([
        makeTask(id: 'a'),
        makeTask(id: 'b', parentId: 'a'),
        makeTask(id: 'c', parentId: 'b'),
        makeTask(id: 'd', parentId: 'c'),
      ]);

      final error = errValue(
        validateParentChange(tasks: tasks, taskId: 'a', newParentId: 'd'),
      );

      expect(error, ParentChangeError.cycle);
    });

    test('accepts a deep move that creates no cycle', () {
      final tasks = byId([
        makeTask(id: 'a'),
        makeTask(id: 'b', parentId: 'a'),
        makeTask(id: 'x'),
        makeTask(id: 'y', parentId: 'x'),
      ]);

      final result = validateParentChange(
        tasks: tasks,
        taskId: 'b',
        newParentId: 'y',
      );

      expect(result, isA<Ok<void, ParentChangeError>>());
    });
  });
}
