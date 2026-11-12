import 'dart:async';
import 'dart:convert';

import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/pull_applier.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';

import 'backoff.dart';
import 'sync_feature.dart';
import 'sync_status.dart';
import 'sync_transport.dart';

/// The user's decision for a conflict.
enum ConflictChoice {
  /// Take the server's state; the local change is discarded (archived).
  useServer,

  /// Apply the local change on top of the server's current state.
  keepLocal,

  /// Apply values chosen by the user (fields of the conflict).
  merge,

  /// For a deleted entity: create a new entity (copy) with the local values.
  recreateCopy,
}

/// The server refused a resolution (for example `strategy_not_allowed`).
final class ResolveRejected implements Exception {
  const ResolveRejected(this.code);

  final String code;

  @override
  String toString() => 'ResolveRejected: $code';
}

/// Points at which a test can interrupt or observe a cycle (crash and fault
/// injection). A hook that throws stops the cycle exactly there.
typedef SyncHook = Future<void> Function(String point);

/// Tuning that can be changed without touching the logic.
final class SyncEngineConfig {
  const SyncEngineConfig({
    this.maxBatch = maxBatchOperations,
    this.pullPageLimit = 200,
    this.maxPullPages = 10000,
    this.maxRetriesPerRun = 6,
  });

  final int maxBatch;
  final int pullPageLimit;
  final int maxPullPages;

  /// Attempts of [SyncEngine.runWithRetry] before it gives up for now.
  final int maxRetriesPerRun;
}

/// The local synchronization engine (S6).
///
/// One cycle: register the device once, push every claimable operation in ordered
/// batches, pull every page since the persisted cursor, then recover blocked
/// operations. It never discards, overwrites or reclassifies local user data:
/// failures keep operations queued (a retry sends the identical operation and the
/// server replays by `operation_id`), refusals stay visible as rejected or
/// conflicted operations, and a pull never overwrites a field with unsent work.
///
/// The engine does nothing unless the feature flag is on ([syncFeatureEnabled]
/// by default) and needs no authentication in tests: [userId] is a callback.
final class SyncEngine {
  SyncEngine({
    required this.transport,
    required this.outbox,
    required this.state,
    required this.pull,
    required this.userId,
    required IdGenerator ids,
    bool? enabled,
    SyncEngineConfig config = const SyncEngineConfig(),
    Backoff? backoff,
    Future<void> Function(Duration)? sleep,
    this.hook,
  }) : enabled = enabled ?? syncFeatureEnabled,
       _ids = ids,
       _config = config,
       _backoff = backoff ?? Backoff(),
       _sleep = sleep ?? Future<void>.delayed,
       _batchLimit = config.maxBatch,
       _status = const SyncStatus(phase: SyncPhase.idle);

  final SyncTransport transport;
  final OutboxStore outbox;
  final SyncStateStore state;
  final PullApplier pull;

  /// The signed-in server user id, or null when signed out.
  final Future<String?> Function() userId;
  final bool enabled;
  final SyncHook? hook;
  final IdGenerator _ids;
  final SyncEngineConfig _config;
  final Backoff _backoff;
  final Future<void> Function(Duration) _sleep;

  int _batchLimit;
  int _attempt = 0;
  SyncStatus _status;
  Future<SyncStatus>? _running;
  final StreamController<SyncStatus> _controller =
      StreamController<SyncStatus>.broadcast();

  SyncStatus get status => _status;

  /// Emits a new status whenever the phase or counts change.
  Stream<SyncStatus> get statuses => _controller.stream;

  Future<void> dispose() => _controller.close();

  // ------------------------------------------------------------ a cycle

  /// Runs one cycle now (also the manual "Sync now" action). Calls made while a
  /// cycle runs share that cycle.
  Future<SyncStatus> syncNow() {
    final running = _running;
    if (running != null) {
      return running;
    }
    final future = _cycle().whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  /// Runs cycles, sleeping with exponential backoff and jitter between failed
  /// attempts, until one succeeds, the problem needs the user, or the retry
  /// budget is spent.
  Future<SyncStatus> runWithRetry() async {
    var result = await syncNow();
    var tries = 0;
    while (result.phase == SyncPhase.retrying &&
        tries < _config.maxRetriesPerRun) {
      await _sleep(_backoff.delay(_attempt - 1));
      tries++;
      result = await syncNow();
    }
    return result;
  }

  Future<SyncStatus> _cycle() async {
    if (!enabled) {
      return _emit(SyncPhase.disabled);
    }
    if (state.paused) {
      return _emit(SyncPhase.deviceRevoked, code: 'paused');
    }
    _emit(SyncPhase.syncing);
    try {
      final user = await userId();
      if (user == null) {
        return _emit(SyncPhase.authRequired, code: 'signed_out');
      }
      state.bindAccount(user);
      outbox.recoverInFlight();
      await _ensureRegistered();
      await _pushAll();
      await _pullAll();
      if (outbox.resubmitBlocked() > 0) {
        await _pushAll();
      }
      state.markSynced();
      _attempt = 0;
      return _emit(SyncPhase.idle);
    } on SyncAuthFailure catch (error) {
      return _emit(
        SyncPhase.authRequired,
        code: error.anonymous ? 'anonymous' : 'auth',
      );
    } on SyncNetworkFailure catch (error) {
      _attempt++;
      return _emit(SyncPhase.retrying, code: error.message);
    } on OutboxProtocolException {
      _attempt++;
      return _emit(SyncPhase.retrying, code: 'protocol');
    } on PullProtocolException {
      _attempt++;
      return _emit(SyncPhase.retrying, code: 'protocol');
    } on _DeviceRevoked {
      state.paused = true;
      return _emit(SyncPhase.deviceRevoked, code: 'device_invalid');
    } on SyncServerError catch (error) {
      return _emit(SyncPhase.error, code: error.code);
    } on RepositoryException catch (error) {
      return _emit(SyncPhase.error, code: 'local: ${error.message}');
    }
  }

  Future<void> _ensureRegistered() async {
    if (state.deviceRegistered) {
      return;
    }
    await _register();
  }

  Future<void> _register() async {
    try {
      await transport.registerDevice(outbox.deviceId());
      state.deviceRegistered = true;
    } on SyncServerError catch (error) {
      if (error.code == 'device_invalid') {
        throw const _DeviceRevoked();
      }
      rethrow;
    }
  }

  // --------------------------------------------------------------- push

  Future<void> _pushAll() async {
    var reRegistered = false;
    while (true) {
      final batch = outbox.claimBatch(maxOperations: _batchLimit);
      if (batch.isEmpty) {
        return;
      }
      final ids = [for (final op in batch) op.operationId];
      await _at('before_push');
      final List<Object?> results;
      try {
        results = await transport.push(outbox.deviceId(), [
          for (final op in batch) op.wire,
        ]);
      } on SyncServerError catch (error) {
        outbox.releaseClaims(ids, error: error.code);
        switch (error.code) {
          case 'device_invalid':
            if (reRegistered) {
              throw const _DeviceRevoked();
            }
            reRegistered = true;
            await _register();
            continue;
          case 'batch_too_large':
          case 'payload_too_large':
            if (_batchLimit <= 1) {
              rethrow;
            }
            _batchLimit = (_batchLimit / 2).floor();
            continue;
          default:
            rethrow;
        }
      } on SyncTransportException catch (error) {
        outbox.releaseClaims(ids, error: error.message);
        rethrow;
      }
      await _at('after_push_response');
      try {
        outbox.acknowledge(ids, results);
      } on OutboxProtocolException {
        outbox.releaseClaims(ids, error: 'protocol');
        rethrow;
      }
      await _at('after_ack');
      if (_batchLimit < _config.maxBatch) {
        _batchLimit = _config.maxBatch;
      }
    }
  }

  // --------------------------------------------------------------- pull

  Future<void> _pullAll() async {
    var cursor = state.cursor();
    var resetOnce = false;
    for (var page = 0; page < _config.maxPullPages; page++) {
      final Map<String, Object?> response;
      try {
        response = await transport.pull(
          outbox.deviceId(),
          cursor,
          limit: _config.pullPageLimit,
        );
      } on SyncServerError catch (error) {
        if (error.code == 'invalid_cursor' && !resetOnce) {
          // The cursor is not from this server's stream (for example the server
          // was restored). Starting over is safe: applying is idempotent and
          // pending local edits are never overwritten.
          state.resetCursor();
          cursor = 0;
          resetOnce = true;
          continue;
        }
        if (error.code == 'device_invalid') {
          throw const _DeviceRevoked();
        }
        rethrow;
      }
      await _at('before_pull_apply');
      final result = pull.applyPage(response);
      await _at('after_pull_apply');
      cursor = result.nextCursor;
      if (!result.hasMore) {
        return;
      }
    }
  }

  // --------------------------------------------------- user decisions

  /// Resolves a conflict with the server and then completes it locally. The
  /// operation id of the resolution is created once per conflict and strategy and
  /// reused by retries, so a lost response never resolves twice.
  Future<void> resolveConflict(
    String conflictId,
    ConflictChoice choice, {
    Map<String, Object?>? values,
  }) async {
    if (!enabled) {
      throw const RepositoryException('synchronization is disabled');
    }
    final conflict = outbox
        .conflictsNeedingAction()
        .where((c) => c['id'] == conflictId)
        .toList();
    if (conflict.isEmpty) {
      throw RepositoryException('no conflict needing a decision: $conflictId');
    }
    final isTree = (jsonDecode(
      conflict.single['client_value_json'] as String,
    ) as Map).containsKey('tree');
    final retryAfterServer = choice == ConflictChoice.keepLocal && isTree;
    final strategy = switch (choice) {
      ConflictChoice.useServer => 'resolved_server',
      ConflictChoice.keepLocal =>
        isTree ? 'resolved_server' : 'resolved_client',
      ConflictChoice.merge => 'resolved_merged',
      ConflictChoice.recreateCopy => 'recreate_copy',
    };
    final key = '$conflictId:$strategy';
    var operationId = state.resolveOperationId(key);
    if (operationId == null) {
      operationId = _ids.nextId();
      state.rememberResolveOperationId(key, operationId);
    }
    final payload = strategy == 'recreate_copy'
        ? {'new_entity_id': _copyId(key)}
        : (strategy == 'resolved_merged' ? values : null);
    final result = await transport.resolveConflict(
      deviceId: outbox.deviceId(),
      operationId: operationId,
      conflictId: conflictId,
      resolution: strategy,
      values: payload,
    );
    if (result['status'] != 'applied') {
      throw ResolveRejected((result['error_code'] as String?) ?? 'rejected');
    }
    if (strategy == 'recreate_copy') {
      final copy = result['row'];
      final type = conflict.single['entity_type'] as String;
      if (copy is Map) {
        pull.applyServerRow(type, Map<String, Object?>.from(copy));
      }
    }
    if (retryAfterServer) {
      outbox.resolveConflictRetryLocal(conflictId);
    } else {
      outbox.applyServerResolution(conflictId, result);
    }
    _emit(_status.phase, code: _status.code);
  }

  /// A stable id for the copy created by one resolution attempt (so a retry of
  /// the same attempt creates the same entity, never two).
  String _copyId(String key) {
    final remembered = state.resolveOperationId('copy:$key');
    if (remembered != null) {
      return remembered;
    }
    final id = _ids.nextId();
    state.rememberResolveOperationId('copy:$key', id);
    return id;
  }

  /// Revokes one of the user's devices through the server. Revoking this device
  /// pauses synchronization (local data stays).
  Future<void> revokeDevice(String targetDeviceId) async {
    final own = outbox.deviceId();
    await transport.revokeDevice(own, targetDeviceId);
    if (targetDeviceId == own) {
      state.paused = true;
      _emit(SyncPhase.deviceRevoked, code: 'revoked_here');
    }
  }

  // ------------------------------------------------------------- helpers

  Future<void> _at(String point) async {
    final h = hook;
    if (h != null) {
      await h(point);
    }
  }

  SyncStatus _emit(SyncPhase phase, {String? code}) {
    final counts = state.counts();
    _status = SyncStatus(
      phase: phase,
      lastSyncedAt: state.lastSyncedAt,
      pending: counts.pending + counts.inFlight,
      openConflicts: counts.openConflicts,
      rejected: counts.rejected,
      staged: counts.staged,
      attempt: _attempt,
      code: code,
    );
    if (!_controller.isClosed) {
      _controller.add(_status);
    }
    return _status;
  }
}

final class _DeviceRevoked implements Exception {
  const _DeviceRevoked();
}
