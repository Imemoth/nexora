import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_panel.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_diagnostics.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/auth_session.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/runtime/sync_runtime.dart';

import '../../support/fake_auth.dart';

final class _FixedClock implements Clock {
  @override
  CalendarDate today() => const CalendarDate(2026, 11, 12);
}

/// A store whose operations fail in a chosen way.
final class _BrokenStore implements SecureStore {
  _BrokenStore(this.error);

  final Object error;

  @override
  Future<String?> read(String key) async => throw error;

  @override
  Future<void> write(String key, String value) async => throw error;

  @override
  Future<void> delete(String key) async => throw error;
}

/// An auth service that fails in an unexpected (non-AuthFailure) way.
final class _ExplodingApi implements AuthApi {
  @override
  Future<AuthSession> signInWithPassword(String email, String password) async =>
      throw StateError('unexpected');

  @override
  Future<AuthSession> refresh(String refreshToken) async =>
      throw StateError('unexpected');

  @override
  Future<void> signOut(String accessToken) async {}
}

void main() {
  late Directory dir;
  late FakeAuthApi api;
  late InMemorySecureStore store;
  var clock = DateTime.utc(2026, 11, 12, 12);

  SyncRuntime build({
    AuthApi? authApi,
    SecureStore? secrets,
    AuthLog log = const NullAuthLog(),
  }) {
    final sessions = SessionManager(
      api: authApi ?? api,
      store: secrets ?? store,
      now: () => clock,
      log: log,
    );
    return SyncRuntime(
      sessions: sessions,
      paths: AccountPaths(dir),
      localDatabasePath: '${dir.path}${Platform.pathSeparator}nexora.db',
      config: null,
      ids: RandomIdGenerator(),
      clock: _FixedClock(),
      autoSyncOnSignIn: false,
      log: log,
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexora-signin-');
    clock = DateTime.utc(2026, 11, 12, 12);
    api = FakeAuthApi(() => clock);
    store = InMemorySecureStore();
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a database handle may still be closing on Windows
    }
  });

  File accountDb(SyncRuntime r, String user) => File(
    '${r.accountFolder(user).path}${Platform.pathSeparator}nexora.db',
  );

  test('first sign-in: account database, session saved, state updated', () async {
    final runtime = build();
    await runtime.start();
    addTearDown(runtime.dispose);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.success);
    expect(runtime.active.userId, userA);
    expect(accountDb(runtime, userA).existsSync(), isTrue);
    expect(await store.read('session'), isNotNull);
    expect(runtime.sessions.state.phase, AuthPhase.signedIn);
  });

  test('restart restores the session and reopens the account', () async {
    final first = build();
    await first.start();
    await first.signIn('a@example.test', 'pw');
    await first.dispose();
    final second = build();
    addTearDown(second.dispose);
    final active = await second.start();
    expect(active.userId, userA);
    expect(second.sessions.state.phase, AuthPhase.signedIn);
  });

  test('a failing protected store does not strand the sign-in', () async {
    final runtime = build(
      secrets: _BrokenStore(const AuthStorageFailure('dpapi_failed')),
    );
    await runtime.start();
    addTearDown(runtime.dispose);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.success);
    expect(runtime.active.userId, userA);
    expect(runtime.sessions.state.reason, AuthReason.storageUnreadable);
  });

  test('an unexpected store exception is contained as well', () async {
    final runtime = build(secrets: _BrokenStore(StateError('boom')));
    await runtime.start();
    addTearDown(runtime.dispose);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.success);
    expect(runtime.sessions.state.reason, AuthReason.storageUnreadable);
  });

  test('an unexpected auth-layer exception releases the dialog (failed)', () async {
    final runtime = build(authApi: _ExplodingApi());
    await runtime.start();
    addTearDown(runtime.dispose);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.failed);
    expect(runtime.active.userId, isNull);
  });

  test(
    'account database failure: error outcome, local data intact, retry works',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      await runtime.active.repository.saveProject(
        const Project(id: 'local-p', name: 'Local work', position: 0),
      );
      // A plain file where the accounts folder must be: creating the account's
      // folder fails.
      final blocker = File('${dir.path}${Platform.pathSeparator}accounts')
        ..writeAsStringSync('in the way');

      expect(
        await runtime.signIn('a@example.test', 'pw'),
        SignInOutcome.accountStorageFailed,
      );
      expect(runtime.active.userId, isNull);
      expect(runtime.sessions.state.phase, AuthPhase.signedOut);
      expect(await store.read('session'), isNull);
      final projects = await runtime.active.repository.loadProjects();
      expect(projects.map((p) => p.name), contains('Local work'));

      blocker.deleteSync();
      expect(
        await runtime.signIn('a@example.test', 'pw'),
        SignInOutcome.success,
      );
      expect(runtime.active.userId, userA);
    },
  );

  test('network failure shows offline and a retry works', () async {
    final runtime = build();
    await runtime.start();
    addTearDown(runtime.dispose);
    api.signInFailures.add(const AuthNetworkFailure('timeout'));
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.offline);
    expect(runtime.active.userId, isNull);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.success);
    expect(runtime.active.userId, userA);
  });

  test('sign out and sign in again keeps the account data', () async {
    final runtime = build();
    await runtime.start();
    addTearDown(runtime.dispose);
    await runtime.signIn('a@example.test', 'pw');
    await runtime.active.repository.saveProject(
      const Project(id: 'acc-p', name: 'Account work', position: 0),
    );
    await runtime.signOut();
    expect(runtime.active.userId, isNull);
    expect(await runtime.signIn('a@example.test', 'pw'), SignInOutcome.success);
    final projects = await runtime.active.repository.loadProjects();
    expect(projects.map((p) => p.name), ['Account work']);
  });

  test('the diagnostic log never holds the password or any token', () async {
    final log = MemoryAuthLog();
    final runtime = build(log: log);
    await runtime.start();
    addTearDown(runtime.dispose);
    await runtime.signIn('a@example.test', 'hunter2-secret-pw');
    final text = log.lines.join('\n');
    expect(text, contains('signin.persist.ok'));
    expect(text, contains('runtime.signin.ok'));
    expect(text.contains('hunter2-secret-pw'), isFalse);
    expect(text.contains('refresh-1'), isFalse);
    expect(text.contains('eyJ'), isFalse); // no JWT
  });

  test('log lines drop secret-looking keys and cut long values', () {
    final line = formatAuthLogLine(DateTime.utc(2026), 'x y', {
      'password': 'p',
      'accessToken': 't',
      'refresh_token': 'r',
      'ok': 'v' * 300,
    });
    expect(line.contains('password'), isFalse);
    expect(line.contains('accessToken'), isFalse);
    expect(line.contains('refresh_token'), isFalse);
    expect(line.contains('x_y'), isTrue);
    expect(line.length, lessThan(220));
  });
}
