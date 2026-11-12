import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_failure.dart';

import '../../support/fake_auth.dart';

/// A local stand-in for the Auth service: it shows exactly what the client sends
/// and lets each test choose the answer.
final class _Server {
  late HttpServer http;
  final requests =
      <({String path, Map<String, String> headers, Object? body})>[];
  int status = 200;
  Object? reply;

  Future<void> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((request) async {
      final text = await utf8.decoder.bind(request).join();
      requests.add((
        path: request.uri.toString(),
        headers: {
          for (final name in ['apikey', 'authorization', 'content-type'])
            name: request.headers.value(name) ?? '',
        },
        body: text.isEmpty ? null : jsonDecode(text),
      ));
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      if (reply != null) request.response.write(jsonEncode(reply));
      await request.response.close();
    });
  }

  String get url => 'http://127.0.0.1:${http.port}';
}

Map<String, Object?> _session(String user, {bool anonymous = false}) => {
  'access_token': fakeJwt(
    sub: user,
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    anonymous: anonymous,
  ),
  'refresh_token': 'rt',
  'expires_in': 3600,
  'user': {'id': user, 'email': 'a@example.test', 'is_anonymous': anonymous},
};

void main() {
  late _Server server;
  late SupabaseAuthApi api;

  setUp(() async {
    server = _Server();
    await server.start();
    api = SupabaseAuthApi(baseUrl: server.url, anonKey: 'anon-key');
  });
  tearDown(() async {
    api.close();
    await server.http.close(force: true);
  });

  test('sign-in posts the password grant with only the public key', () async {
    server.reply = _session(userA);

    final session = await api.signInWithPassword('a@example.test', 'pw');

    expect(session.userId, userA);
    expect(session.isAnonymous, isFalse);
    expect(session.refreshToken, 'rt');
    final r = server.requests.single;
    expect(r.path, '/auth/v1/token?grant_type=password');
    expect(r.headers['apikey'], 'anon-key');
    expect(r.headers['authorization'], '');
    expect(r.body, {'email': 'a@example.test', 'password': 'pw'});
  });

  test('an anonymous session is reported as anonymous', () async {
    server.reply = _session(userA, anonymous: true);
    final session = await api.signInWithPassword('a@example.test', 'pw');
    expect(session.isAnonymous, isTrue);
  });

  test(
    'wrong credentials, unconfirmed email and throttling are told apart',
    () async {
      server
        ..status = 400
        ..reply = {
          'code': 400,
          'error_code': 'invalid_credentials',
          'msg': 'Invalid login credentials',
        };
      await expectLater(
        api.signInWithPassword('a', 'b'),
        throwsA(isA<AuthInvalidCredentials>()),
      );
      server.reply = {
        'code': 400,
        'error_code': 'email_not_confirmed',
        'msg': 'Email not confirmed',
      };
      await expectLater(
        api.signInWithPassword('a', 'b'),
        throwsA(isA<AuthUnconfirmed>()),
      );
      server
        ..status = 429
        ..reply = {'code': 429, 'error_code': 'over_request_rate_limit'};
      await expectLater(
        api.signInWithPassword('a', 'b'),
        throwsA(isA<AuthRateLimited>()),
      );
      server
        ..status = 503
        ..reply = null;
      await expectLater(
        api.signInWithPassword('a', 'b'),
        throwsA(isA<AuthNetworkFailure>()),
      );
    },
  );

  test(
    'refresh posts the refresh grant; a refused token means revoked',
    () async {
      server.reply = _session(userA);
      await api.refresh('old-refresh');
      final r = server.requests.single;
      expect(r.path, '/auth/v1/token?grant_type=refresh_token');
      expect(r.body, {'refresh_token': 'old-refresh'});

      server
        ..status = 400
        ..reply = {
          'code': 400,
          'error_code': 'refresh_token_not_found',
          'msg': 'Invalid Refresh Token',
        };
      await expectLater(
        api.refresh('old-refresh'),
        throwsA(isA<AuthSessionRevoked>()),
      );
      server
        ..status = 403
        ..reply = {
          'code': 403,
          'error_code': 'user_not_found',
          'msg': 'User from sub claim in JWT does not exist',
        };
      await expectLater(
        api.refresh('old-refresh'),
        throwsA(isA<AuthSessionRevoked>()),
      );
      server
        ..status = 500
        ..reply = null;
      await expectLater(
        api.refresh('old-refresh'),
        throwsA(isA<AuthNetworkFailure>()),
      );
    },
  );

  test(
    'sign-out sends the bearer token and tolerates an already ended session',
    () async {
      server
        ..status = 204
        ..reply = null;
      await api.signOut('access');
      expect(server.requests.single.path, '/auth/v1/logout?scope=local');
      expect(server.requests.single.headers['authorization'], 'Bearer access');
      server.status = 401;
      await api.signOut('access');
    },
  );

  test('an unreachable service is a network failure', () async {
    await server.http.close(force: true);
    await expectLater(
      api.signInWithPassword('a', 'b'),
      throwsA(isA<AuthNetworkFailure>()),
    );
  });

  test('a malformed session body is a server failure', () async {
    server.reply = {'access_token': 'x'};
    await expectLater(
      api.signInWithPassword('a', 'b'),
      throwsA(isA<AuthServerFailure>()),
    );
  });
}
