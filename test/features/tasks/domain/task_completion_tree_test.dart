import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_completion_tree.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/task_fixtures.dart';

void main() {
  group('completionOf', () {
    test('all direct children done is eligible for review', () {
      final tasks = byId([
        makeTask(id: 'parent'),
        makeTask(id: 'c1', parentId: 'parent', status: TaskStatus.done),
        makeTask(id: 'c2', parentId: 'parent', status: TaskStatus.done),
      ]);

      final completion = completionOf('parent', tasks);

      expect(completion.total, 2);
      expect(completion.done, 2);
      expect(completion.eligibleForReview, isTrue);
    });

    test('never changes the parent status', () {
      final tasks = byId([
        makeTask(id: 'parent'),
        makeTask(id: 'c1', parentId: 'parent', status: TaskStatus.done),
      ]);

      completionOf('parent', tasks);

      expect(tasks['parent']!.status, TaskStatus.open);
    });

    test('grandchildren do not count toward the parent', () {
      final tasks = byId([
        makeTask(id: 'parent'),
        makeTask(id: 'child', parentId: 'parent'),
        makeTask(id: 'grandchild', parentId: 'child', status: TaskStatus.done),
      ]);

      final completion = completionOf('parent', tasks);

      expect(completion.total, 1);
      expect(completion.done, 0);
      expect(completion.eligibleForReview, isFalse);
    });

    test('a task with no children is not eligible for review', () {
      final tasks = byId([makeTask(id: 'leaf')]);

      final completion = completionOf('leaf', tasks);

      expect(completion.total, 0);
      expect(completion.eligibleForReview, isFalse);
    });

    test('archived children count toward total but not done', () {
      final tasks = byId([
        makeTask(id: 'parent'),
        makeTask(id: 'c1', parentId: 'parent', status: TaskStatus.archived),
      ]);

      final completion = completionOf('parent', tasks);

      expect(completion.total, 1);
      expect(completion.done, 0);
      expect(completion.eligibleForReview, isFalse);
    });
  });
}
