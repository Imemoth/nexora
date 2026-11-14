import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task.dart';
import 'package:nexora/features/tasks/domain/task_completion_tree.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_search.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

import 'nav_selection.dart';
import 'visible_task_row.dart';

/// Whether [task] belongs to [selection] on [today], ignoring search.
bool inSelection(Task task, NavSelection selection, CalendarDate today) {
  return switch (selection) {
    SmartViewSelection(:final view) => matchesSmartView(task, view, today),
    ProjectSelection(:final projectId) => task.projectId == projectId,
  };
}

/// Whether [task] belongs to [selection] and matches [query].
bool matchesFilter(
  Task task,
  NavSelection selection,
  String query,
  CalendarDate today,
) {
  return inSelection(task, selection, today) && matchesSearch(task, query);
}

/// Flattened, sorted rows for the list.
///
/// Children appear only under expanded parents. A child whose parent does not
/// match the filter is shown at the top level.
List<VisibleTaskRow> buildVisibleRows({
  required Map<String, Task> tasks,
  required NavSelection selection,
  required String query,
  required TaskSort sort,
  required Set<String> expandedIds,
  required CalendarDate today,
  TaskStatus? status,
}) {
  final matching = [
    for (final task in tasks.values)
      if (matchesFilter(task, selection, query, today) &&
          (status == null || task.status == status))
        task,
  ];
  final entries = flattenTasks(
    tasks: matching,
    sort: sort,
    expandedIds: expandedIds,
  );
  return [
    for (final entry in entries)
      VisibleTaskRow(
        task: entry.task,
        depth: entry.depth,
        hasChildren: entry.hasChildren,
        expanded: expandedIds.contains(entry.task.id),
        completion: entry.hasChildren
            ? completionOf(entry.task.id, tasks)
            : null,
      ),
  ];
}
