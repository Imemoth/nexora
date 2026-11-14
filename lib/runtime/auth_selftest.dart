import 'dart:async';
import 'dart:io';

import 'package:nexora/app/account_panel.dart';
import 'package:nexora/app/system_clock.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_diagnostics.dart';
import 'package:nexora/features/auth/auth_session.dart';
import 'package:nexora/features/auth/native_dpapi.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/runtime/sync_runtime.dart';

/// Development self-test of the sign-in lifecycle, run INSIDE the real packaged
/// executable (a Windows GUI process without a console), with no network and no
/// UI: protected-store round trips with both implementations, then a full
/// sign-in, restart, sign-out and second sign-in through [SyncRuntime] against a
/// throw-away folder. Every step is logged with its duration to [outPath];
/// secrets never appear (the values stored are fixed test strings).
///
/// Started only when the build has synchronization enabled and the environment
/// variable `NEXORA_AUTH_SELFTEST` names an output file. Returns the exit code.
Future<int> runAuthSelfTest(String outPath) async {
  final log = FileAuthLog(File(outPath));
  var failures = 0;
  Future<void> step(String name, Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    log.log('selftest.step.start', {'step': name});
    try {
      await body().timeout(const Duration(seconds: 90));
      log.log('selftest.step.ok', {
        'step': name,
        'ms': watch.elapsedMilliseconds,
      });
    } on Object catch (error) {
      failures++;
      log.log('selftest.step.failed', {
        'step': name,
        'type': error.runtimeType,
        'detail': '$error',
        'ms': watch.elapsedMilliseconds,
      });
    }
  }

  log.log('selftest.start', {
    'stdinTerminal': stdin.hasTerminal,
    'stdoutTerminal': stdout.hasTerminal,
    'os': Platform.operatingSystemVersion,
  });
  final root = Directory.systemTemp.createTempSync('nexora-selftest-');
  try {
    final powershell = DpapiSecureStore(
      Directory('${root.path}${Platform.pathSeparator}ps'),
      protector: PowerShellProtector(log: log),
      log: log,
    );
    await step('powershell store round trip', () async {
      await powershell.write('session', 'selftest-value-ps');
      final back = await powershell.read('session');
      if (back != 'selftest-value-ps') {
        throw StateError('powershell round trip mismatch');
      }
    });
    final nativeDir = Directory('${root.path}${Platform.pathSeparator}native');
    await step('native store round trip', () async {
      final native = DpapiSecureStore(
        nativeDir,
        protector: NativeDpapiProtector(),
        log: log,
      );
      await native.write('session', 'selftest-value-native');
      if (await native.read('session') != 'selftest-value-native') {
        throw StateError('native round trip mismatch');
      }
    });
    await step('native reads a value written by powershell', () async {
      final native = DpapiSecureStore(
        Directory('${root.path}${Platform.pathSeparator}ps'),
        protector: NativeDpapiProtector(),
        log: log,
      );
      if (await native.read('session') != 'selftest-value-ps') {
        throw StateError('cross read mismatch');
      }
    });

    const user = '00000000-0000-4000-8000-0000000000aa';
    final api = _SelfTestApi(user);
    final store = DpapiSecureStore(
      Directory('${root.path}${Platform.pathSeparator}session'),
      protector: NativeDpapiProtector(),
      log: log,
    );
    SyncRuntime build() => SyncRuntime(
      sessions: SessionManager(api: api, store: store, log: log),
      paths: AccountPaths(root),
      localDatabasePath: '${root.path}${Platform.pathSeparator}nexora.db',
      config: null,
      ids: RandomIdGenerator(),
      clock: const SystemClock(),
      autoSyncOnSignIn: false,
      log: log,
    );

    var runtime = build();
    await step('start signed out', () async {
      final active = await runtime.start();
      if (active.userId != null) {
        throw StateError('expected the local workspace');
      }
    });
    await step('sign in opens the account workspace', () async {
      final outcome = await runtime.signIn('selftest@example.test', 'x');
      if (outcome != SignInOutcome.success || runtime.active.userId != user) {
        throw StateError('sign-in outcome $outcome');
      }
      final db = File(
        '${runtime.accountFolder(user).path}${Platform.pathSeparator}nexora.db',
      );
      if (!db.existsSync()) {
        throw StateError('account database was not created');
      }
    });
    await runtime.dispose();
    runtime = build();
    await step('restart restores the session and the account', () async {
      final active = await runtime.start();
      if (active.userId != user) {
        throw StateError('session was not restored');
      }
    });
    await step('sign out then sign in again', () async {
      await runtime.signOut();
      if (runtime.active.userId != null) {
        throw StateError('still signed in');
      }
      final outcome = await runtime.signIn('selftest@example.test', 'x');
      if (outcome != SignInOutcome.success || runtime.active.userId != user) {
        throw StateError('second sign-in outcome $outcome');
      }
    });
    await runtime.dispose();
  } on Object catch (error) {
    failures++;
    log.log('selftest.crashed', {
      'type': error.runtimeType,
      'detail': '$error',
    });
  } finally {
    try {
      root.deleteSync(recursive: true);
    } on Object {
      // best effort
    }
  }
  log.log('selftest.result', {'ok': failures == 0, 'failures': failures});
  return failures == 0 ? 0 : 1;
}

/// A sign-in service that needs no network.
final class _SelfTestApi implements AuthApi {
  _SelfTestApi(this.userId);

  final String userId;

  AuthSession _session() => AuthSession(
    accessToken: 'selftest.access.token',
    refreshToken: 'selftest-refresh-token',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    userId: userId,
    email: 'selftest@example.test',
    isAnonymous: false,
  );

  @override
  Future<AuthSession> signInWithPassword(String email, String password) async =>
      _session();

  @override
  Future<AuthSession> refresh(String refreshToken) async => _session();

  @override
  Future<void> signOut(String accessToken) async {}
}
