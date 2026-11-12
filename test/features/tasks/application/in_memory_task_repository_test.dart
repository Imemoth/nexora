import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/in_memory_task_repository.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  group('InMemoryTaskRepository', () {
    test('returns the seeded projects and tasks', () async {
      final repo = InMemoryTaskRepository(
        projects: testProjects,
        tasks: [makeTask(id: 'a')],
      );

      expect((await repo.loadProjects()).map((p) => p.id), ['p1', 'p2']);
      expect((await repo.loadTasks()).map((t) => t.id), ['a']);
    });

    test('saveTask inserts, replaces by id and records every save', () async {
      final repo = InMemoryTaskRepository(
        projects: testProjects,
        tasks: [makeTask(id: 'a', title: 'Old')],
      );

      await repo.saveTask(makeTask(id: 'a', title: 'New'));
      await repo.saveTask(makeTask(id: 'b'));

      final tasks = await repo.loadTasks();
      expect(tasks.map((t) => t.id).toSet(), {'a', 'b'});
      expect(tasks.firstWhere((t) => t.id == 'a').title, 'New');
      expect(repo.savedTasks.map((t) => t.id), ['a', 'b']);
    });

    test('loadTasks returns a copy that cannot change storage', () async {
      final repo = InMemoryTaskRepository(
        projects: testProjects,
        tasks: [makeTask(id: 'a')],
      );

      (await repo.loadTasks()).clear();

      expect(await repo.loadTasks(), hasLength(1));
    });

    test(
      'failNextSave rejects one save and leaves storage unchanged',
      () async {
        final repo = InMemoryTaskRepository(
          projects: testProjects,
          tasks: [makeTask(id: 'a', title: 'Old')],
        );
        repo.failNextSave = true;

        await expectLater(
          repo.saveTask(makeTask(id: 'a', title: 'New')),
          throwsA(isA<RepositoryException>()),
        );
        expect(repo.savedTasks, isEmpty);
        expect((await repo.loadTasks()).single.title, 'Old');

        await repo.saveTask(makeTask(id: 'a', title: 'New'));
        expect((await repo.loadTasks()).single.title, 'New');
      },
    );

    test('failNextLoad rejects one load', () async {
      final repo = InMemoryTaskRepository(
        projects: testProjects,
        tasks: [makeTask(id: 'a')],
      );
      repo.failNextLoad = true;

      await expectLater(repo.loadTasks(), throwsA(isA<RepositoryException>()));
      expect(await repo.loadTasks(), hasLength(1));
    });
  });
}
