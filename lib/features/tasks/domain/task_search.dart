import 'task.dart';

/// Case-insensitive substring match over title and notes. A blank query
/// matches every task.
bool matchesSearch(Task task, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return true;
  }
  final inTitle = task.title.toLowerCase().contains(needle);
  final inNotes = task.notes.toLowerCase().contains(needle);
  return inTitle || inNotes;
}
