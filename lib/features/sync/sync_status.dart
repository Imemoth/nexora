/// Where synchronization stands, in terms the user can act on.
enum SyncPhase {
  /// The feature flag is off: nothing runs.
  disabled,

  /// Everything sent and pulled at the last attempt.
  idle,
  syncing,

  /// The network or the server failed; the same work is retried with backoff.
  retrying,

  /// Sign-in is needed. Nothing is lost; pending work waits.
  authRequired,

  /// This device was revoked. Synchronization is paused; local data is kept.
  deviceRevoked,

  /// The server refused something the engine cannot fix by itself (see [SyncStatus.code]).
  error,
}

/// A snapshot for the UI. Counts come from the local file.
final class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.lastSyncedAt,
    this.pending = 0,
    this.openConflicts = 0,
    this.rejected = 0,
    this.staged = 0,
    this.attempt = 0,
    this.code,
  });

  final SyncPhase phase;
  final DateTime? lastSyncedAt;

  /// Changes waiting to be sent.
  final int pending;

  /// Conflicts waiting for a decision.
  final int openConflicts;

  /// Operations the server refused; local data is kept until the user decides.
  final int rejected;

  /// Pulled rows waiting for a parent.
  final int staged;

  /// Consecutive failed attempts (drives the backoff).
  final int attempt;

  /// A stable code for the last problem, for support and tests (never user data).
  final String? code;

  /// Something needs the user: a conflict or a refused change.
  bool get needsAttention => openConflicts > 0 || rejected > 0;
}
