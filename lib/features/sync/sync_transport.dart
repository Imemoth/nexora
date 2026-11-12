/// The wire between the sync engine and a server. The engine only knows this
/// interface, so it runs against a fake in tests, against PostgreSQL in the
/// integration tests, and against Supabase (disabled by default) in the app.
///
/// Every method maps to one RPC of the S2/S3/S4 wire contract. Failures are
/// reported as [SyncTransportException]s so the engine can decide what is
/// retryable, what needs the user, and what must stop:
/// - [SyncNetworkFailure]: nothing reliable was received (timeout, connection
///   lost, HTTP 5xx, transient database errors). Retry the same request.
/// - [SyncAuthFailure]: no valid session. Pending work stays queued.
/// - [SyncServerError]: the server refused the call with a stable code
///   (`device_invalid`, `device_limit`, `batch_too_large`, `payload_too_large`,
///   `invalid_cursor`, `invalid_request`, ...).
abstract interface class SyncTransport {
  /// `nexora_register_device`. Idempotent for an active device.
  Future<Map<String, Object?>> registerDevice(String deviceId, {String? label});

  /// `nexora_sync_push`: returns the `results` list in input order.
  Future<List<Object?>> push(String deviceId, List<Map<String, Object?>> operations);

  /// `nexora_sync_pull`: returns `{changes, conflicts, next_cursor, has_more}`.
  Future<Map<String, Object?>> pull(String deviceId, int cursor, {int limit = 200});

  /// `nexora_resolve_conflict`: returns the result object (`status` applied or
  /// rejected).
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  });

  /// `nexora_revoke_device`.
  Future<Map<String, Object?>> revokeDevice(String deviceId, String targetDeviceId);
}

/// Base of every transport failure.
sealed class SyncTransportException implements Exception {
  const SyncTransportException(this.message);

  /// Diagnostic text; never shown to users verbatim and never contains user data.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The request may or may not have reached the server. The engine retries the
/// identical request; the server replays by `operation_id`, so this is safe.
final class SyncNetworkFailure extends SyncTransportException {
  const SyncNetworkFailure(super.message);
}

/// There is no valid session (signed out, token expired, anonymous user, deleted
/// user). Pending work is kept; the user must sign in again.
final class SyncAuthFailure extends SyncTransportException {
  const SyncAuthFailure(super.message, {this.anonymous = false});

  /// An anonymous identity can never synchronize.
  final bool anonymous;
}

/// The server refused the call with a stable error [code] (the RPC's message).
final class SyncServerError extends SyncTransportException {
  const SyncServerError(this.code, [String? detail]) : super(detail ?? code);

  final String code;
}
