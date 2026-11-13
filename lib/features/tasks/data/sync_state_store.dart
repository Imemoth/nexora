import 'package:nexora/features/tasks/application/repository_exception.dart';

import 'local_database.dart';

/// What the user needs to see about synchronization, read from the local file.
final class SyncCounts {
  const SyncCounts({
    required this.pending,
    required this.inFlight,
    required this.openConflicts,
    required this.rejected,
    required this.staged,
  });

  /// Operations waiting to be sent.
  final int pending;
  final int inFlight;

  /// Conflicts that still need a decision (local mirror).
  final int openConflicts;

  /// Rejected operations nobody has handled yet (local data is preserved).
  final int rejected;

  /// Pulled rows waiting for their parent.
  final int staged;
}

/// Small persistent facts about synchronization: the pull cursor, the account
/// the file is bound to, whether the device is registered, and in-progress
/// resolution identifiers (so a retried resolution reuses its operation id).
final class SyncStateStore {
  SyncStateStore(this._db, {DateTime Function()? now})
    : _now = now ?? (() => DateTime.now().toUtc());

  final LocalDatabase _db;
  final DateTime Function() _now;

  void _ensureRow() {
    _db.raw.execute('INSERT OR IGNORE INTO sync_state (singleton) VALUES (1)');
  }

  /// The last applied pull cursor. Cursor values are not contiguous.
  int cursor() {
    _ensureRow();
    return _db.raw
            .select('SELECT cursor FROM sync_state WHERE singleton = 1')
            .single['cursor']
        as int;
  }

  /// Forgets the cursor so the next pull starts from the beginning. Safe: applying
  /// a pulled row is idempotent and never overwrites pending local edits.
  void resetCursor() {
    _ensureRow();
    _db.raw.execute('UPDATE sync_state SET cursor = 0 WHERE singleton = 1');
  }

  bool get paused {
    _ensureRow();
    return _db.raw
            .select('SELECT state FROM sync_state WHERE singleton = 1')
            .single['state'] ==
        'paused';
  }

  set paused(bool value) {
    _ensureRow();
    _db.raw.execute('UPDATE sync_state SET state = ? WHERE singleton = 1', [
      value ? 'paused' : 'idle',
    ]);
  }

  /// The server account this file synchronizes with, or null before the first
  /// synchronization.
  String? get accountUserId => _meta('account_user_id');

  /// Binds the file to [userId] on first use. A different account is refused and
  /// nothing changes: a local database never mixes two accounts.
  void bindAccount(String userId) {
    final existing = accountUserId;
    if (existing == null) {
      _setMeta('account_user_id', userId);
      return;
    }
    if (existing != userId) {
      throw const RepositoryException(
        'this database is bound to another account',
      );
    }
  }

  bool get deviceRegistered => _meta('device_registered') == '1';

  set deviceRegistered(bool value) =>
      _setMeta('device_registered', value ? '1' : '0');

  DateTime? get lastSyncedAt {
    final value = _meta('last_synced_at');
    return value == null ? null : DateTime.parse(value);
  }

  void markSynced() =>
      _setMeta('last_synced_at', _now().toUtc().toIso8601String());

  /// The operation id used for resolving [conflictId], created once and reused by
  /// every retry so the server replays instead of applying twice.
  String? resolveOperationId(String conflictId) =>
      _meta('resolve_op:$conflictId');

  void rememberResolveOperationId(String conflictId, String operationId) =>
      _setMeta('resolve_op:$conflictId', operationId);

  SyncCounts counts() {
    int count(String sql) => _db.raw.select(sql).single['n'] as int;
    return SyncCounts(
      pending: count(
        "SELECT COUNT(*) AS n FROM sync_outbox WHERE state = 'pending'",
      ),
      inFlight: count(
        "SELECT COUNT(*) AS n FROM sync_outbox WHERE state = 'in_flight'",
      ),
      // Conflicts that still need the user: the local operation is unhandled
      // (this includes one another device already resolved on the server: the
      // local change still waits for a decision here).
      openConflicts: count(
        'SELECT COUNT(*) AS n FROM sync_conflicts_local c '
        'JOIN sync_outbox o ON o.operation_id = c.operation_id '
        "WHERE o.state = 'conflict' AND o.handled_at_utc IS NULL",
      ),
      rejected: count(
        "SELECT COUNT(*) AS n FROM sync_outbox WHERE state = 'rejected' AND handled_at_utc IS NULL",
      ),
      staged: count('SELECT COUNT(*) AS n FROM sync_pull_stage'),
    );
  }

  String? _meta(String key) {
    final rows = _db.raw.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  void _setMeta(String key, String value) {
    _db.raw.execute(
      'INSERT INTO meta (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }
}
