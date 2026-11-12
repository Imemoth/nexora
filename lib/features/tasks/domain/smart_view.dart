import 'calendar_date.dart';
import 'task.dart';
import 'task_status.dart';

/// Predefined task lists shown in the left navigation.
enum SmartView { today, next7Days, overdue, all }

bool _isOpen(TaskStatus status) {
  return status != TaskStatus.done && status != TaskStatus.archived;
}

bool _isWithinNextWeek(CalendarDate due, CalendarDate today) {
  final afterToday = due.compareTo(today) > 0;
  final withinWeek = due.compareTo(today.addDays(7)) <= 0;
  return afterToday && withinWeek;
}

/// Whether [task] belongs in [view] for the local date [today].
///
/// "Open" means neither done nor archived. [SmartView.all] shows every task,
/// including archived ones.
bool matchesSmartView(Task task, SmartView view, CalendarDate today) {
  if (view == SmartView.all) {
    return true;
  }
  final due = task.dueDate;
  if (due == null || !_isOpen(task.status)) {
    return false;
  }
  return switch (view) {
    SmartView.today => due == today,
    SmartView.next7Days => _isWithinNextWeek(due, today),
    SmartView.overdue => due.compareTo(today) < 0,
    SmartView.all => true,
  };
}
