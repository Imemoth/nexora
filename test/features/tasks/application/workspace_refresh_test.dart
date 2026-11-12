import 'package:flutter_test/flutter_test.dart';

import '../../../support/task_fixtures.dart';
import '../../../support/workspace_harness.dart';

void main() {
  test('refresh picks up stored changes and adds the pulled task', () async {
    final h = await loadedHarness(tasks: sampleTasks());
    await h.repository.saveTask(
      makeTask(id: 'z', title: 'Pulled from the server'),
    );

    expect(await h.workspace.refresh(), isTrue);

    expect(h.workspace.state.tasks.containsKey('z'), isTrue);
  });

  test('refresh never replaces the workspace while a draft is open', () async {
    final h = await loadedHarness(tasks: sampleTasks());
    h.workspace.requestSelectTask('a');
    h.workspace.editDraft(title: 'Typing…');
    await h.repository.saveTask(makeTask(id: 'z', title: 'Pulled'));

    expect(await h.workspace.refresh(), isFalse);

    expect(h.workspace.state.draft, isNotNull);
    expect(h.workspace.state.tasks.containsKey('z'), isFalse);
  });
}
