import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'auth_failure.dart';
import 'auth_session.dart';

/// The calls the application makes to the authentication service. Faked in unit
/// tests; the real implementation is [SupabaseAuthApi].
abstract interface class AuthApi {
  /// Email and password sign-in. Throws an [AuthFailure].
  Future<AuthSession> signInWithPassword(String email, String password);

  /// Exchanges a refresh token for a new session (the old refresh token is
  /// consumed). Throws [AuthSessionRevoked] when the service refuses it.
  Future<AuthSession> refresh(String refreshToken);

  /// Ends the session on the server (best effort; the caller always forgets the
  /// local tokens).
  Future<void> signOut(String accessToken);
}

/// Supabase Auth (GoTrue) over `dart:io`. It sends only the project's public
/// (anon) key and the user's own tokens: the service-role key never appears in
/// the application.
final class SupabaseAuthApi implements AuthApi {
  SupabaseAuthApi({
    required this.baseUrl,
    required this.anonKey,
    HttpClient? client,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? HttpClient(),
       _now = now ?? (() => DateTime.now().toUtc());

  /// The project URL without a trailing slash.
  final String baseUrl;
  final String anonKey;
  final Duration timeout;
  final HttpClient _client;
  final DateTime Function() _now;

  @override
  Future<AuthSession> signInWithPassword(String email, String password) async {
    final response = await _post('/auth/v1/token?grant_type=password', {
      'email': email,
      'password': password,
    });
    if (response.status == 200) {
      return _session(response.body);
    }
    throw _signInFailure(response);
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _post('/auth/v1/token?grant_type=refresh_token', {
      'refresh_token': refreshToken,
    });
    if (response.status == 200) {
      return _session(response.body);
    }
    throw _refreshFailure(response);
  }

  @override
  Future<void> signOut(String accessToken) async {
    final response = await _post(
      '/auth/v1/logout?scope=local',
      const {},
      bearer: accessToken,
    );
    if (response.status >= 200 && response.status < 300) {
      return;
    }
    if (response.status == 401 || response.status == 403) {
      return; // already gone on the server
    }
    throw _transient(response) ??
        AuthServerFailure('logout_${response.status}');
  }

  AuthSession _session(Object? body) {
    if (body is! Map) {
      throw const AuthServerFailure('malformed_session');
    }
    final access = body['access_token'];
    final refresh = body['refresh_token'];
    final user = body['user'];
    if (access is! String || refresh is! String || user is! Map) {
      throw const AuthServerFailure('malformed_session');
    }
    final id = user['id'];
    if (id is! String || id.isEmpty) {
      throw const AuthServerFailure('malformed_session');
    }
    final claims = JwtClaims.parse(access);
    final expiresAtSeconds = body['expires_at'];
    final expiresIn = body['expires_in'];
    final DateTime expiresAt;
    if (claims?.expiresAt != null) {
      expiresAt = claims!.expiresAt!;
    } else if (expiresAtSeconds is int) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtSeconds * 1000,
        isUtc: true,
      );
    } else if (expiresIn is int) {
      expiresAt = _now().add(Duration(seconds: expiresIn));
    } else {
      throw const AuthServerFailure('malformed_session');
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: expiresAt,
      userId: id.toLowerCase(),
      email: user['email'] is String ? user['email'] as String : null,
      isAnonymous: user['is_anonymous'] == true || claims?.isAnonymous == true,
    );
  }

  AuthFailure _signInFailure(_Response r) {
    final transient = _transient(r);
    if (transient != null) {
      return transient;
    }
    final code = r.errorCode;
    if (code == 'email_not_confirmed' ||
        r.text.contains('Email not confirmed')) {
      return const AuthUnconfirmed();
    }
    if (code == 'invalid_credentials' ||
        r.text.contains('Invalid login credentials') ||
        r.status == 400 ||
        r.status == 401) {
      return const AuthInvalidCredentials();
    }
    return AuthServerFailure('signin_${r.status}');
  }

  AuthFailure _refreshFailure(_Response r) {
    final transient = _transient(r);
    if (transient != null) {
      return transient;
    }
    if (r.status == 400 ||
        r.status == 401 ||
        r.status == 403 ||
        r.status == 404 ||
        r.status == 422) {
      return AuthSessionRevoked(r.errorCode ?? 'refresh_${r.status}');
    }
    return AuthServerFailure('refresh_${r.status}');
  }

  AuthFailure? _transient(_Response r) {
    if (r.status == 429) {
      return const AuthRateLimited();
    }
    if (r.status >= 500 || r.status == 408) {
      return AuthNetworkFailure('http_${r.status}');
    }
    return null;
  }

  Future<_Response> _post(
    String path,
    Map<String, Object?> body, {
    String? bearer,
  }) async {
    try {
      final request = await _client
          .postUrl(Uri.parse('$baseUrl$path'))
          .timeout(timeout);
      request.headers
        ..set('apikey', anonKey)
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json');
      if (bearer != null) {
        request.headers.set('Authorization', 'Bearer $bearer');
      }
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _Response(response.statusCode, text);
    } on TimeoutException {
      throw const AuthNetworkFailure('timeout');
    } on SocketException {
      throw const AuthNetworkFailure('connection');
    } on HttpException {
      throw const AuthNetworkFailure('http');
    } on HandshakeException {
      throw const AuthNetworkFailure('tls');
    }
  }

  void close() => _client.close(force: true);
}

final class _Response {
  _Response(this.status, this.text);

  final int status;
  final String text;

  Object? get body {
    if (text.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  String? get errorCode {
    final b = body;
    if (b is Map) {
      final code = b['error_code'] ?? b['error'];
      return code is String ? code : null;
    }
    return null;
  }
}
