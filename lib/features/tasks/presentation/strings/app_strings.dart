import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/smart_view.dart';
import 'package:nexora/features/tasks/domain/task_ordering.dart';
import 'package:nexora/features/tasks/domain/task_priority.dart';
import 'package:nexora/features/tasks/domain/task_status.dart';

/// Every user-visible string in Phase 1. English, centralized for later
/// localization. Widgets must not contain visible-text literals.
abstract final class AppStrings {
  static const appName = 'Nexora';
  static const projectsHeader = 'Projects';
  static const selectTaskPrompt = 'Select a task';
  static const noTasksHere = 'No tasks here yet';
  static const emptyProject = 'No tasks in this project yet';
  static const noSearchMatches = 'No tasks match your search';
  static const clearSearch = 'Clear';
  static const searchHint = 'Search title and notes';
  static const selectedTaskHidden = 'Selected task is hidden in this view';
  static const readyForReview = 'Ready for review';
  static const sortTooltip = 'Sort';
  static const expandTask = 'Expand';
  static const collapseTask = 'Collapse';
  static const fieldStatus = 'Status';
  static const fieldPriority = 'Priority';
  static const fieldDue = 'Due';
  static const fieldNotes = 'Notes';
  static const noDueDate = 'No due date';
  static const noNotes = 'No notes';

  static String smartViewLabel(SmartView view) {
    return switch (view) {
      SmartView.today => 'Today',
      SmartView.next7Days => 'Next 7 Days',
      SmartView.overdue => 'Overdue',
      SmartView.all => 'All',
    };
  }

  static String taskCount(int count) {
    return count == 1 ? '1 task' : '$count tasks';
  }

  static String progress(int done, int total) => '$done/$total';

  static String dueLabel(CalendarDate date) => 'Due ${date.toIsoString()}';

  static String sortLabel(TaskSort sort) {
    return switch (sort) {
      TaskSort.position => 'Position',
      TaskSort.dueDate => 'Due date',
      TaskSort.priority => 'Priority',
      TaskSort.title => 'Title',
    };
  }

  static String statusLabel(TaskStatus status) {
    return switch (status) {
      TaskStatus.open => 'Open',
      TaskStatus.inProgress => 'In progress',
      TaskStatus.review => 'Review',
      TaskStatus.done => 'Done',
      TaskStatus.archived => 'Archived',
    };
  }

  static String priorityLabel(TaskPriority priority) {
    return switch (priority) {
      TaskPriority.none => 'No priority',
      TaskPriority.low => 'Low',
      TaskPriority.medium => 'Medium',
      TaskPriority.high => 'High',
    };
  }
}
