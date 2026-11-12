import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_transport.dart';

/// [SyncTransport] over Supabase PostgREST (`/rest/v1/rpc/<function>`), using only
/// `dart:io`. **Disabled by default and not wired into the app**: nothing
/// constructs it unless the synchronization flag and an authentication layer are
/// added (slice S7). It never holds a service-role key: it sends the project's
/// public (anon) key and the signed-in user's access token.
///
/// Error mapping follows docs/architecture/s3-s4-wire-contract.md section 4: a
/// PostgREST error body `{code, message}` carries the SQLSTATE and the RPC's
/// error code (the message).
final class SupabaseSyncTransport implements SyncTransport {
  SupabaseSyncTransport({
    required this.baseUrl,
    required this.anonKey,
    required this.accessToken,
    HttpClient? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? HttpClient();

  /// The project URL, for example `https://<ref>.supabase.co` (no trailing slash).
  final String baseUrl;
  final String anonKey;

  /// The current access token, or null when signed out.
  final Future<String?> Function() accessToken;
  final Duration timeout;
  final HttpClient _client;

  static const Set<String> _knownServerCodes = {
    'device_invalid',
    'device_limit',
    'batch_too_large',
    'payload_too_large',
    'invalid_request',
    'invalid_cursor',
  };

  @override
  Future<Map<String, Object?>> registerDevice(
    String deviceId, {
    String? label,
  }) async {
    return _object(
      await _rpc('nexora_register_device', {
        'p_device_id': deviceId,
        'p_label': label,
      }),
    );
  }

  @override
  Future<List<Object?>> push(
    String deviceId,
    List<Map<String, Object?>> operations,
  ) async {
    final body = _object(
      await _rpc('nexora_sync_push', {
        'p_device_id': deviceId,
        'p_ops': operations,
      }),
    );
    final results = body['results'];
    if (results is! List) {
      throw const SyncNetworkFailure('malformed_push_response');
    }
    return results;
  }

  @override
  Future<Map<String, Object?>> pull(
    String deviceId,
    int cursor, {
    int limit = 200,
  }) async {
    return _object(
      await _rpc('nexora_sync_pull', {
        'p_device_id': deviceId,
        'p_cursor': cursor,
        'p_limit': limit,
      }),
    );
  }

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) async {
    return _object(
      await _rpc('nexora_resolve_conflict', {
        'p_device_id': deviceId,
        'p_operation_id': operationId,
        'p_conflict_id': conflictId,
        'p_resolution': resolution,
        'p_values': values,
      }),
    );
  }

  @override
  Future<Map<String, Object?>> revokeDevice(
    String deviceId,
    String targetDeviceId,
  ) async {
    return _object(
      await _rpc('nexora_revoke_device', {
        'p_device_id': deviceId,
        'p_target_device_id': targetDeviceId,
      }),
    );
  }

  Map<String, Object?> _object(Object? value) {
    if (value is! Map) {
      throw const SyncNetworkFailure('malformed_response');
    }
    return Map<String, Object?>.from(value);
  }

  Future<Object?> _rpc(String function, Map<String, Object?> body) async {
    final token = await accessToken();
    if (token == null || token.isEmpty) {
      throw const SyncAuthFailure('no_session');
    }
    try {
      final request = await _client
          .postUrl(Uri.parse('$baseUrl/rest/v1/rpc/$function'))
          .timeout(timeout);
      request.headers
        ..set('apikey', anonKey)
        ..set('Authorization', 'Bearer $token')
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return text.isEmpty ? null : jsonDecode(text);
      }
      throw _classify(response.statusCode, text);
    } on SyncTransportException {
      rethrow;
    } on TimeoutException {
      throw const SyncNetworkFailure('timeout');
    } on SocketException {
      throw const SyncNetworkFailure('connection');
    } on HttpException {
      throw const SyncNetworkFailure('http');
    } on HandshakeException {
      throw const SyncNetworkFailure('tls');
    } on FormatException {
      throw const SyncNetworkFailure('malformed_response');
    }
  }

  SyncTransportException _classify(int status, String text) {
    String? sqlstate;
    String? message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        sqlstate = decoded['code'] as String?;
        message = decoded['message'] as String?;
      }
    } on FormatException {
      // not JSON: classify by status alone
    }
    if (status == 401 ||
        sqlstate == '28000' ||
        (sqlstate != null && sqlstate.startsWith('PGRST3'))) {
      return const SyncAuthFailure('unauthenticated');
    }
    if (sqlstate == '42501' && message == 'anonymous_not_allowed') {
      return const SyncAuthFailure('anonymous_not_allowed', anonymous: true);
    }
    if (status >= 500 || status == 429 || status == 408) {
      return SyncNetworkFailure('http_$status');
    }
    if (sqlstate != null &&
        (sqlstate.startsWith('40') ||
            sqlstate.startsWith('53') ||
            sqlstate.startsWith('55') ||
            sqlstate.startsWith('57'))) {
      return SyncNetworkFailure('transient_$sqlstate');
    }
    if (message != null && _knownServerCodes.contains(message)) {
      return SyncServerError(message);
    }
    if (sqlstate == 'NX001') return const SyncServerError('device_invalid');
    if (sqlstate == 'NX002') return const SyncServerError('device_limit');
    if (sqlstate == 'NX003') return const SyncServerError('batch_too_large');
    if (sqlstate == 'NX004') return const SyncServerError('payload_too_large');
    if (sqlstate == 'NX005') return const SyncServerError('invalid_request');
    if (sqlstate == 'NX006') return const SyncServerError('invalid_cursor');
    return SyncServerError(message ?? 'http_$status');
  }

  void close() => _client.close(force: true);
}
