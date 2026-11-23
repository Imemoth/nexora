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

/// A short piece of a task's Notes around the first search match, split so the
/// UI can emphasise the match. Whitespace and line breaks are collapsed to single
/// spaces. [leading] and [trailing] say that the excerpt starts or ends inside
/// the notes (the UI shows an ellipsis there).
final class NotesExcerpt {
  const NotesExcerpt({
    required this.before,
    required this.match,
    required this.after,
    required this.leading,
    required this.trailing,
  });

  final String before;
  final String match;
  final String after;
  final bool leading;
  final bool trailing;

  /// The plain text of the excerpt, ellipses included.
  String get text =>
      '${leading ? '…' : ''}$before$match$after${trailing ? '…' : ''}';
}

/// Why a task is in the results of [query], when only its Notes explain it.
///
/// Returns null when there is nothing to explain: a blank query, a title match
/// (the title shows why), or no match in the notes. This is presentation only:
/// it uses the same trimmed, case-insensitive substring test as
/// [matchesSearch] and never changes which tasks match.
NotesExcerpt? notesMatchExcerpt(Task task, String query, {int radius = 32}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty || task.title.toLowerCase().contains(needle)) {
    return null;
  }
  final notes = task.notes;
  final lower = notes.toLowerCase();
  final at = lower.indexOf(needle);
  if (at < 0) {
    return null;
  }
  String tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
  if (lower.length != notes.length) {
    // A character whose lower-case form has another length (rare) shifts the
    // positions: show the start of the notes without a highlight.
    final head = tidy(notes.trim());
    final cut = head.length > radius * 2 ? head.substring(0, radius * 2) : head;
    return NotesExcerpt(
      before: cut.trimRight(),
      match: '',
      after: '',
      leading: false,
      trailing: cut.length < head.length,
    );
  }
  final end = at + needle.length;
  final from = (at - radius).clamp(0, at);
  final to = (end + radius).clamp(end, notes.length);
  final before = tidy(notes.substring(from, at));
  final after = tidy(notes.substring(end, to));
  return NotesExcerpt(
    before: from > 0 ? before.trimLeft() : before,
    match: tidy(notes.substring(at, end)),
    after: to < notes.length ? after.trimRight() : after,
    leading: from > 0,
    trailing: to < notes.length,
  );
}
