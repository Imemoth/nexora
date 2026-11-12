import 'package:nexora/features/sync/sync_transport.dart';

/// Stands in for the real HTTP adapter's first step: every call asks for the access
/// token (which is what makes the session manager refresh an expired one, or report
/// that there is no session) before the request reaches the fake server.
final class TokenGate implements SyncTransport {
  TokenGate(this.inner, this.token);

  final SyncTransport inner;
  final Future<String?> Function() token;

  Future<void> _gate() async {
    final value = await token();
    if (value == null || value.isEmpty) {
      throw const SyncAuthFailure('no_session');
    }
  }

  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) async {
    await _gate();
    return inner.registerDevice(deviceId, label: label);
  }

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) async {
    await _gate();
    return inner.push(deviceId, operations);
  }

  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) async {
    await _gate();
    return inner.pull(deviceId, cursor, limit: limit);
  }

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) async {
    await _gate();
    return inner.resolveConflict(
      deviceId: deviceId,
      operationId: operationId,
      conflictId: conflictId,
      resolution: resolution,
      values: values,
    );
  }

  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) async {
    await _gate();
    return inner.revokeDevice(deviceId, targetDeviceId);
  }
}
