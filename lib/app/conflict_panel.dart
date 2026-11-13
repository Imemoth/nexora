import 'package:nexora/features/sync/conflicts.dart';
import 'package:nexora/features/sync/sync_engine.dart';

/// What the conflict screens need, and nothing else: the unresolved conflicts
/// and the way to decide them. Provided only for a signed-in account while
/// synchronization is on. Widgets never read the database.
final class ConflictPanel {
  const ConflictPanel({
    required this.load,
    required this.changes,
    required this.resolve,
  });

  /// The unresolved conflicts right now (oldest first).
  final List<ConflictView> Function() load;

  /// Fires whenever the set of conflicts may have changed.
  final Stream<void> changes;

  /// Sends a decision. Returns only after the outcome is known.
  final Future<ConflictOutcome> Function(
    String id,
    ConflictChoice choice, {
    Map<String, MergePick>? picks,
  })
  resolve;
}
