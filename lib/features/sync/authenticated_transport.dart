import 'sync_transport.dart';
import 'token_source.dart';

/// Wraps a transport with the two guards every real call needs:
/// 1. **Account binding.** Before every call the signed-in account must be the
///    account this database is bound to. A different account (someone signed in
///    as another user while a cycle was running) stops the call with an
///    authentication failure; nothing is sent.
/// 2. **One refresh and one retry** when the server rejects the token as
///    unauthenticated (an anonymous identity is never retried).
/// Replays are safe: every operation carries its `operation_id`.
final class AuthenticatedTransport implements SyncTransport {
  AuthenticatedTransport({
    required SyncTransport inner,
    required TokenSource tokens,
    required String boundUserId,
  }) : _inner = inner,
       _tokens = tokens,
       _bound = boundUserId.toLowerCase();

  final SyncTransport _inner;
  final TokenSource _tokens;
  final String _bound;

  Future<T> _call<T>(Future<T> Function() call) async {
    _checkAccount();
    try {
      return await call();
    } on SyncAuthFailure catch (error) {
      if (error.anonymous) {
        rethrow;
      }
      if (!await _tokens.refreshAfterRejection()) {
        rethrow;
      }
      _checkAccount();
      return call();
    }
  }

  void _checkAccount() {
    final current = _tokens.userId?.toLowerCase();
    if (current == null) {
      throw const SyncAuthFailure('signed_out');
    }
    if (current != _bound) {
      throw const SyncAuthFailure('account_mismatch');
    }
  }

  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) => _call(() => _inner.registerDevice(deviceId, label: label));

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) => _call(() => _inner.push(deviceId, operations));

  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) => _call(() => _inner.pull(deviceId, cursor, limit: limit));

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) => _call(
    () => _inner.resolveConflict(
      deviceId: deviceId,
      operationId: operationId,
      conflictId: conflictId,
      resolution: resolution,
      values: values,
    ),
  );

  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) => _call(() => _inner.revokeDevice(deviceId, targetDeviceId));
}
