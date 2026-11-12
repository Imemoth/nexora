import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/auth_session.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';

import '../../support/fake_auth.dart';

void main() {
  var clock = DateTime.utc(2026, 11, 12, 12);
  DateTime now() => clock;

  late FakeAuthApi api;
  late InMemorySecureStore store;
  late SessionManager manager;

  SessionManager build() => SessionManager(api: api, store: store, now: now);

  setUp(() {
    clock = DateTime.utc(2026, 11, 12, 12);
    api = FakeAuthApi(now);
    store = InMemorySecureStore();
    manager = build();
  });

  group('claims', () {
    test('parse subject, expiry, role and the anonymous flag', () {
      final token = fakeJwt(
        sub: userA.toUpperCase(),
        expiresAt: DateTime.utc(2030),
        anonymous: true,
      );
      final claims = JwtClaims.parse(token)!;
      expect(claims.subject, userA);
      expect(claims.isAnonymous, isTrue);
      expect(claims.role, 'authenticated');
      expect(claims.expiresAt, DateTime.utc(2030));
    });

    test('garbage is not a token', () {
      expect(JwtClaims.parse('nope'), isNull);
      expect(JwtClaims.parse('a.b.c'), isNull);
      expect(
        JwtClaims.parse('a.${base64Url.encode(utf8.encode('[]'))}.c'),
        isNull,
      );
    });
  });

  group('sign in and restore', () {
    test('sign-in stores the session and restore needs no network', () async {
      await manager.signIn('a@example.test', 'pw');
      expect(manager.state.phase, AuthPhase.signedIn);
      expect(manager.userId, userA);

      final again = build();
      final restored = await again.restore();
      expect(restored.phase, AuthPhase.signedIn);
      expect(again.userId, userA);
      expect(api.refreshes, 0);
      expect(api.signIns, 1);
    });

    test('an anonymous identity is rejected and nothing is stored', () async {
      api.anonymousNext = true;
      await expectLater(
        manager.signIn('a@example.test', 'pw'),
        throwsA(isA<AuthAnonymousRejected>()),
      );
      expect(manager.state.phase, AuthPhase.signedOut);
      expect(await store.read('session'), isNull);
      expect(api.signOuts, 1); // the throwaway session is ended
    });

    test('a failed sign-in changes nothing', () async {
      await manager.signIn('a@example.test', 'pw');
      api.signInFailures.add(const AuthInvalidCredentials());
      await expectLater(
        manager.signIn('b@example.test', 'wrong'),
        throwsA(isA<AuthInvalidCredentials>()),
      );
      expect(manager.userId, userA);
    });

    test('a damaged stored record is treated as signed out', () async {
      await store.write('session', '{not json');
      final restored = await manager.restore();
      expect(restored.phase, AuthPhase.signedOut);
      expect(await store.read('session'), isNull);
    });

    test('a stored anonymous session is dropped on restore', () async {
      final session = AuthSession(
        accessToken: fakeJwt(
          sub: userA,
          expiresAt: DateTime.utc(2030),
          anonymous: true,
        ),
        refreshToken: 'r',
        expiresAt: DateTime.utc(2030),
        userId: userA,
        email: null,
        isAnonymous: true,
      );
      await store.write('session', jsonEncode(session.toJson()));
      final restored = await manager.restore();
      expect(restored.phase, AuthPhase.signedOut);
      expect(restored.reason, AuthReason.anonymousRejected);
    });

    test('account switch replaces the session and the account id', () async {
      await manager.signIn('a@example.test', 'pw');
      await manager.signIn('b@example.test', 'pw');
      expect(manager.userId, userB);
      expect(await store.read('last_user'), userB);
    });
  });

  group('refresh', () {
    test(
      'a token about to expire is refreshed and the rotation stored',
      () async {
        await manager.signIn('a@example.test', 'pw');
        final first = manager.state.session!;
        clock = clock.add(const Duration(minutes: 59, seconds: 30));

        final token = await manager.accessToken();

        expect(api.refreshes, 1);
        expect(token, isNot(first.accessToken));
        final stored = AuthSession.fromJson(
          jsonDecode((await store.read('session'))!),
        )!;
        expect(stored.refreshToken, manager.state.session!.refreshToken);
        expect(stored.refreshToken, isNot(first.refreshToken));
      },
    );

    test('concurrent callers share one refresh', () async {
      await manager.signIn('a@example.test', 'pw');
      api.refreshDelay = const Duration(milliseconds: 30);
      clock = clock.add(const Duration(minutes: 59, seconds: 30));

      final tokens = await Future.wait([
        manager.accessToken(),
        manager.accessToken(),
        manager.accessToken(),
      ]);

      expect(api.refreshes, 1);
      expect(tokens.toSet(), hasLength(1));
    });

    test('offline: a token that is still valid keeps working', () async {
      await manager.signIn('a@example.test', 'pw');
      final session = manager.state.session!;
      clock = clock.add(const Duration(minutes: 59, seconds: 30));
      api.refreshFailures.add(const AuthNetworkFailure('connection'));

      expect(await manager.accessToken(), session.accessToken);
      expect(manager.state.phase, AuthPhase.signedIn);
    });

    test('offline and expired: an error, the session is kept', () async {
      await manager.signIn('a@example.test', 'pw');
      clock = clock.add(const Duration(hours: 2));
      api.refreshFailures.add(const AuthNetworkFailure('connection'));

      await expectLater(
        manager.accessToken(),
        throwsA(isA<AuthNetworkFailure>()),
      );
      expect(manager.state.phase, AuthPhase.signedIn);
      expect(await store.read('session'), isNotNull);
    });

    test(
      'a revoked session needs a new sign-in and keeps the account id',
      () async {
        await manager.signIn('a@example.test', 'pw');
        clock = clock.add(const Duration(hours: 2));
        api.refreshFailures.add(const AuthSessionRevoked('session_not_found'));

        expect(await manager.accessToken(), isNull);

        expect(manager.state.phase, AuthPhase.reauthRequired);
        expect(manager.state.userId, userA);
        expect(manager.userId, isNull);
        expect(await store.read('session'), isNull);
        expect(await store.read('last_user'), userA);

        final restarted = build();
        final restored = await restarted.restore();
        expect(restored.phase, AuthPhase.reauthRequired);
        expect(restored.userId, userA);
      },
    );

    test('a refresh that returns another account is refused', () async {
      await manager.signIn('a@example.test', 'pw');
      clock = clock.add(const Duration(hours: 2));
      api.refreshAs = userB;

      expect(await manager.accessToken(), isNull);
      expect(manager.state.phase, AuthPhase.reauthRequired);
      expect(manager.state.userId, userA);
    });

    test(
      'refreshAfterRejection refreshes once and reports the result',
      () async {
        await manager.signIn('a@example.test', 'pw');
        expect(await manager.refreshAfterRejection(), isTrue);
        api.refreshFailures.add(const AuthSessionRevoked('revoked'));
        expect(await manager.refreshAfterRejection(), isFalse);
        expect(manager.state.phase, AuthPhase.reauthRequired);
      },
    );
  });

  group('sign out', () {
    test('clears the tokens and the account hint, even offline', () async {
      await manager.signIn('a@example.test', 'pw');
      api.signOutFailures.add(const AuthNetworkFailure('connection'));

      final state = await manager.signOut();

      expect(state.phase, AuthPhase.signedOut);
      expect(await store.read('session'), isNull);
      expect(await store.read('last_user'), isNull);
      expect(await manager.accessToken(), isNull);
    });
  });
}
