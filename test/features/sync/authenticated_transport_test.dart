import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/sync/authenticated_transport.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/sync/token_source.dart';

import '../../support/fake_auth.dart';
import '../../support/fake_sync_server.dart';

final class _Tokens implements TokenSource {
  @override
  String? userId = userA;
  bool refreshResult = true;
  int refreshes = 0;

  @override
  Future<String?> accessToken() async => 'token';

  @override
  Future<bool> refreshAfterRejection() async {
    refreshes++;
    return refreshResult;
  }
}

void main() {
  test('calls pass through for the bound account', () async {
    final server = FakeSyncServer();
    final transport = AuthenticatedTransport(
      inner: server,
      tokens: _Tokens(),
      boundUserId: userA.toUpperCase(),
    );
    await transport.registerDevice('d1');
    expect(server.log, contains('register'));
  });

  test('a different signed-in account stops the call before anything is sent', () async {
    final server = FakeSyncServer();
    final tokens = _Tokens()..userId = userB;
    final transport = AuthenticatedTransport(
      inner: server,
      tokens: tokens,
      boundUserId: userA,
    );
    await expectLater(
      transport.push('d1', const []),
      throwsA(
        isA<SyncAuthFailure>().having((e) => e.message, 'message', 'account_mismatch'),
      ),
    );
    expect(server.log, isEmpty);
  });

  test('signed out is an authentication failure, not a network failure', () async {
    final server = FakeSyncServer();
    final tokens = _Tokens()..userId = null;
    final transport = AuthenticatedTransport(
      inner: server,
      tokens: tokens,
      boundUserId: userA,
    );
    await expectLater(
      transport.pull('d1', 0),
      throwsA(isA<SyncAuthFailure>()),
    );
  });

  test('an unauthenticated answer refreshes once and retries once', () async {
    final server = FakeSyncServer();
    final faulty = FaultyTransport(server)
      ..pullFaults.add(const SyncAuthFailure('unauthenticated'));
    final tokens = _Tokens();
    final transport = AuthenticatedTransport(
      inner: faulty,
      tokens: tokens,
      boundUserId: userA,
    );
    await transport.registerDevice('d1');
    final page = await transport.pull('d1', 0);
    expect(page['has_more'], isFalse);
    expect(tokens.refreshes, 1);
  });

  test('a refresh that fails surfaces the authentication failure', () async {
    final faulty = FaultyTransport(FakeSyncServer())
      ..pullFaults.add(const SyncAuthFailure('unauthenticated'));
    final tokens = _Tokens()..refreshResult = false;
    final transport = AuthenticatedTransport(
      inner: faulty,
      tokens: tokens,
      boundUserId: userA,
    );
    await expectLater(transport.pull('d1', 0), throwsA(isA<SyncAuthFailure>()));
    expect(tokens.refreshes, 1);
  });

  test('an anonymous identity is never retried', () async {
    final faulty = FaultyTransport(FakeSyncServer())
      ..pullFaults.add(const SyncAuthFailure('anonymous_not_allowed', anonymous: true));
    final tokens = _Tokens();
    final transport = AuthenticatedTransport(
      inner: faulty,
      tokens: tokens,
      boundUserId: userA,
    );
    await expectLater(transport.pull('d1', 0), throwsA(isA<SyncAuthFailure>()));
    expect(tokens.refreshes, 0);
  });

  test('a second rejection after the retry is not retried again', () async {
    final faulty = FaultyTransport(FakeSyncServer())
      ..pullFaults.addAll(const [
        SyncAuthFailure('unauthenticated'),
        SyncAuthFailure('unauthenticated'),
      ]);
    final tokens = _Tokens();
    final transport = AuthenticatedTransport(
      inner: faulty,
      tokens: tokens,
      boundUserId: userA,
    );
    await expectLater(transport.pull('d1', 0), throwsA(isA<SyncAuthFailure>()));
    expect(tokens.refreshes, 1);
  });
}
