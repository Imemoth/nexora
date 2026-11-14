import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/task_deletion.dart';

import '../../../support/task_fixtures.dart';

void main() {
  group('leafFirstDeletionOrder', () {
    test('a task with no children deletes alone', () {
      final tasks = byId([makeTask(id: 'a')]);

      expect(leafFirstDeletionOrder(tasks, ['a']), ['a']);
    });

    test('children come before their parent, deepest first', () {
      final tasks = byId([
        makeTask(id: 'root'),
        makeTask(id: 'kid1', parentId: 'root', position: 0),
        makeTask(id: 'kid2', parentId: 'root', position: 1),
        makeTask(id: 'grand', parentId: 'kid1'),
      ]);

      final order = leafFirstDeletionOrder(tasks, ['root']);

      expect(order, ['grand', 'kid1', 'kid2', 'root']);
    });

    test('other branches are left alone', () {
      final tasks = byId([
        makeTask(id: 'root'),
        makeTask(id: 'kid', parentId: 'root'),
        makeTask(id: 'other'),
        makeTask(id: 'other-kid', parentId: 'other'),
      ]);

      expect(leafFirstDeletionOrder(tasks, ['root']), ['kid', 'root']);
    });

    test('unknown ids are ignored and ids are never repeated', () {
      final tasks = byId([makeTask(id: 'a'), makeTask(id: 'b', parentId: 'a')]);

      expect(leafFirstDeletionOrder(tasks, ['missing', 'a', 'b']), ['b', 'a']);
    });
  });

  group('projectDeletionOrder', () {
    test('lists every task of the project, leaf-first, and no others', () {
      final tasks = byId([
        makeTask(id: 'p1-root'),
        makeTask(id: 'p1-kid', parentId: 'p1-root'),
        makeTask(id: 'p2-root', projectId: 'p2'),
      ]);

      final order = projectDeletionOrder(tasks, 'p1');

      expect(order, ['p1-kid', 'p1-root']);
    });

    test('an empty project has nothing to delete', () {
      final tasks = byId([makeTask(id: 'x', projectId: 'p2')]);

      expect(projectDeletionOrder(tasks, 'p1'), isEmpty);
    });
  });
}
