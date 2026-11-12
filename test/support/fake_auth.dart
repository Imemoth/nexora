import 'dart:convert';

import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/auth_session.dart';

String _b64(Object json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// An unsigned token with the claims the client reads (tests only; the real
/// server verifies signatures).
String fakeJwt({
  required String sub,
  required DateTime expiresAt,
  bool anonymous = false,
  String role = 'authenticated',
}) =>
    '${_b64({'alg': 'none'})}.${_b64({'sub': sub, 'exp': expiresAt.millisecondsSinceEpoch ~/ 1000, 'is_anonymous': anonymous, 'role': role})}.sig';

const String userA = '11111111-1111-4111-8111-111111111111';
const String userB = '22222222-2222-4222-8222-222222222222';

/// A scriptable [AuthApi]. Counts calls; failures are queued per method.
final class FakeAuthApi implements AuthApi {
  FakeAuthApi(this.now);

  final DateTime Function() now;
  Duration lifetime = const Duration(hours: 1);
  int signIns = 0;
  int refreshes = 0;
  int signOuts = 0;
  int _serial = 0;
  final List<AuthFailure> signInFailures = [];
  final List<AuthFailure> refreshFailures = [];
  final List<AuthFailure> signOutFailures = [];
  Duration refreshDelay = Duration.zero;
  bool anonymousNext = false;
  String? userFor;

  /// When set, a refresh issues a session for this user instead of the owner.
  String? refreshAs;
  final Map<String, String> _owner = {};

  /// Refresh tokens the service still accepts (rotation: each is used once).
  final Set<String> validRefreshTokens = {};

  AuthSession _issue(String user, {bool anonymous = false}) {
    _serial++;
    final expires = now().add(lifetime);
    final refresh = 'refresh-$_serial';
    validRefreshTokens.add(refresh);
    _owner[refresh] = user;
    return AuthSession(
      accessToken: fakeJwt(
        sub: user,
        expiresAt: expires,
        anonymous: anonymous,
      ),
      refreshToken: refresh,
      expiresAt: expires,
      userId: user,
      email: '$user@example.test',
      isAnonymous: anonymous,
    );
  }

  @override
  Future<AuthSession> signInWithPassword(String email, String password) async {
    signIns++;
    if (signInFailures.isNotEmpty) throw signInFailures.removeAt(0);
    final user = email.startsWith('b') ? userB : userA;
    final anonymous = anonymousNext;
    anonymousNext = false;
    return _issue(userFor ?? user, anonymous: anonymous);
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshes++;
    if (refreshDelay > Duration.zero) await Future<void>.delayed(refreshDelay);
    if (refreshFailures.isNotEmpty) throw refreshFailures.removeAt(0);
    if (!validRefreshTokens.remove(refreshToken)) {
      throw const AuthSessionRevoked('refresh_token_not_found');
    }
    return _issue(refreshAs ?? _owner[refreshToken] ?? userA);
  }

  @override
  Future<void> signOut(String accessToken) async {
    signOuts++;
    if (signOutFailures.isNotEmpty) throw signOutFailures.removeAt(0);
  }
}
