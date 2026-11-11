import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_creation_rules.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import '../../../support/result_matchers.dart';
import '../../../support/sequential_id_generator.dart';
import '../../../support/task_fixtures.dart';

const _p1 = Project(id: 'p1', name: 'Home', position: 0);
const _p2 = Project(id: 'p2', name: 'Work', position: 1);
const _projects = {'p1': _p1, 'p2': _p2};

Task _createRoot(
  String title, {
  Iterable<Task> tasks = const [],
  String projectId = 'p1',
  List<String> ids = const ['new-1'],
}) {
  return okValue(
    createRootTask(
      title: title,
      projectId: projectId,
      projects: _projects,
      tasks: tasks,
      ids: SequentialIdGenerator(ids),
    ),
  );
}

void main() {
  group('createRootTask', () {
    test('sets id, trimmed title and documented defaults', () {
      final task = _createRoot('  Pay rent  ');

      expect(task.id, 'new-1');
      expect(task.title, 'Pay rent');
      expect(task.projectId, 'p1');
      expect(task.parentId, isNull);
      expect(task.status, TaskStatus.open);
      expect(task.priority, TaskPriority.none);
      expect(task.dueDate, isNull);
      expect(task.notes, '');
    });

    test('starts at position 0 in an empty project', () {
      expect(_createRoot('First').position, 0);
    });

    test('appends after the highest root position in the same project', () {
      final existing = [
        makeTask(id: 'a', position: 0),
        makeTask(id: 'b', position: 1),
        makeTask(id: 'c', position: 5),
      ];

      expect(_createRoot('Next', tasks: existing).position, 6);
    });

    test('ignores subtasks and other projects when computing position', () {
      final existing = [
        makeTask(id: 'a', position: 2),
        makeTask(id: 'child', parentId: 'a', position: 40),
        makeTask(id: 'other', projectId: 'p2', position: 90),
      ];

      expect(_createRoot('Next', tasks: existing).position, 3);
    });

    test('rejects an empty title', () {
      final result = createRootTask(
        title: '   ',
        projectId: 'p1',
        projects: _projects,
        tasks: const [],
        ids: SequentialIdGenerator(['new-1']),
      );

      expect(errValue(result), CreateError.titleRequired);
    });

    test('rejects a title longer than the maximum', () {
      final result = createRootTask(
        title: 'x' * 201,
        projectId: 'p1',
        projects: _projects,
        tasks: const [],
        ids: SequentialIdGenerator(['new-1']),
      );

      expect(errValue(result), CreateError.titleTooLong);
    });

    test('rejects an unknown project', () {
      final result = createRootTask(
        title: 'Task',
        projectId: 'missing',
        projects: _projects,
        tasks: const [],
        ids: SequentialIdGenerator(['new-1']),
      );

      expect(errValue(result), CreateError.unknownProject);
    });

    test('rejects an id that already exists', () {
      final result = createRootTask(
        title: 'Task',
        projectId: 'p1',
        projects: _projects,
        tasks: [makeTask(id: 'taken')],
        ids: SequentialIdGenerator(['taken']),
      );

      expect(errValue(result), CreateError.idCollision);
    });

    test('does not modify the input task list', () {
      final existing = [makeTask(id: 'a', position: 0)];

      _createRoot('Another', tasks: existing);

      expect(existing, hasLength(1));
      expect(existing.single.id, 'a');
    });
  });

  group('createSubtask', () {
    test('inherits project, sets parent and starts at position 0', () {
      final parent = makeTask(id: 'parent', projectId: 'p2');

      final child = okValue(
        createSubtask(
          title: 'Draft outline',
          parentId: 'parent',
          tasks: [parent],
          ids: SequentialIdGenerator(['child-1']),
        ),
      );

      expect(child.id, 'child-1');
      expect(child.projectId, 'p2');
      expect(child.parentId, 'parent');
      expect(child.position, 0);
      expect(child.status, TaskStatus.open);
    });

    test('appends after existing siblings only', () {
      final tasks = [
        makeTask(id: 'parent'),
        makeTask(id: 's1', parentId: 'parent', position: 0),
        makeTask(id: 's2', parentId: 'parent', position: 4),
        makeTask(id: 'root-other', position: 30),
      ];

      final child = okValue(
        createSubtask(
          title: 'Next',
          parentId: 'parent',
          tasks: tasks,
          ids: SequentialIdGenerator(['new']),
        ),
      );

      expect(child.position, 5);
    });

    test('successive subtasks keep creation order', () {
      final ids = SequentialIdGenerator(['c1', 'c2', 'c3']);
      final tasks = <Task>[makeTask(id: 'parent')];

      for (var i = 0; i < 3; i++) {
        final child = okValue(
          createSubtask(
            title: 'Step $i',
            parentId: 'parent',
            tasks: tasks,
            ids: ids,
          ),
        );
        tasks.add(child);
      }

      final positions = tasks
          .where((t) => t.parentId == 'parent')
          .map((t) => t.position)
          .toList();
      expect(positions, [0, 1, 2]);
    });

    test('rejects an unknown parent', () {
      final result = createSubtask(
        title: 'Orphan',
        parentId: 'ghost',
        tasks: [makeTask(id: 'a')],
        ids: SequentialIdGenerator(['new']),
      );

      expect(errValue(result), CreateError.unknownParent);
    });

    test('rejects an archived parent', () {
      final result = createSubtask(
        title: 'Late',
        parentId: 'parent',
        tasks: [makeTask(id: 'parent', status: TaskStatus.archived)],
        ids: SequentialIdGenerator(['new']),
      );

      expect(errValue(result), CreateError.parentArchived);
    });

    test('rejects an empty title', () {
      final result = createSubtask(
        title: '',
        parentId: 'parent',
        tasks: [makeTask(id: 'parent')],
        ids: SequentialIdGenerator(['new']),
      );

      expect(errValue(result), CreateError.titleRequired);
    });

    test('does not change the parent status', () {
      final parent = makeTask(id: 'parent', status: TaskStatus.done);

      okValue(
        createSubtask(
          title: 'Extra',
          parentId: 'parent',
          tasks: [parent],
          ids: SequentialIdGenerator(['new']),
        ),
      );

      expect(parent.status, TaskStatus.done);
    });
  });
}
