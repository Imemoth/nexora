import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';

import '../../../support/workspace_harness.dart';

/// Phase 5 changes how rows look, never which rows appear. This test lists the
/// rows (id and depth) of every smart view, every project, three searches and
/// every sort, collapsed and fully expanded, for the demo data, and compares
/// them with a baseline recorded on `main` before Phase 5
/// (`test/fixtures/phase5/visibility_baseline.txt`).
///
/// To record the baseline on a revision, run with `UPDATE_VISIBILITY=1`.
const _baselinePath = 'test/fixtures/phase5/visibility_baseline.txt';

Future<String> _enumerate() async {
  final demo = buildDemoData(testToday);
  final harness = await loadedHarness(
    tasks: demo.tasks,
    projects: demo.projects,
  );
  final ws = harness.workspace;
  final parents = {
    for (final task in demo.tasks)
      if (task.parentId != null) task.parentId!,
  };
  final selections = <(String, void Function(TaskWorkspace))>[
    for (final view in SmartView.values)
      ('view:${view.name}', (w) => w.requestSelectView(view)),
    for (final project in demo.projects)
      ('project:${project.id}', (w) => w.requestSelectProject(project.id)),
  ];
  final out = StringBuffer();
  for (final (name, select) in selections) {
    for (final query in const ['', 'a', 'plan']) {
      for (final sort in TaskSort.values) {
        for (final expanded in [false, true]) {
          select(ws);
          ws.requestSearch(query);
          ws.requestSort(sort);
          for (final parent in parents) {
            final isOpen = ws.state.expandedTaskIds.contains(parent);
            if (isOpen != expanded) {
              ws.toggleExpanded(parent);
            }
          }
          final rows = ws.state.visibleRows
              .map((r) => '${r.task.id}:${r.depth}')
              .join(',');
          out.writeln('$name|q=$query|${sort.name}|open=$expanded|$rows');
        }
      }
    }
  }
  return out.toString();
}

void main() {
  test(
    'the rows of every view, project, search and sort are unchanged',
    () async {
      final actual = await _enumerate();
      final file = File(_baselinePath);
      if (Platform.environment['UPDATE_VISIBILITY'] == '1') {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(actual);
        return;
      }
      expect(
        file.existsSync(),
        isTrue,
        reason: 'record the baseline on main with UPDATE_VISIBILITY=1',
      );
      expect(actual, file.readAsStringSync());
    },
  );
}
