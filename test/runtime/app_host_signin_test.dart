import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/app/account_actions.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/runtime/app_host.dart';
import 'package:nexora/runtime/sync_runtime.dart';

import '../support/fake_auth.dart';

final class _FixedClock implements Clock {
  @override
  CalendarDate today() => const CalendarDate(2026, 11, 12);
}

/// The sign-in path end to end through the real UI: dialog, runtime, account
/// database, workspace swap. Only the network is replaced.
void main() {
  late Directory dir;
  late FakeAuthApi api;
  late SyncRuntime runtime;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexora-host-');
    api = FakeAuthApi(() => DateTime.utc(2026, 11, 12, 12));
  });

  /// Built inside the test body, so its futures and streams live in the same
  /// (fake-async) zone as the widgets that await them.
  SyncRuntime makeRuntime() => SyncRuntime(
    sessions: SessionManager(api: api, store: InMemorySecureStore()),
    paths: AccountPaths(dir),
    localDatabasePath: '${dir.path}${Platform.pathSeparator}nexora.db',
    config: null,
    ids: RandomIdGenerator(),
    clock: _FixedClock(),
    autoSyncOnSignIn: false,
  );

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a database handle may still be closing on Windows
    }
  });

  /// Unmounts the app first, then closes the runtime outside the fake-async
  /// zone (closing streams the mounted tree still listens to would never end).
  Future<void> shutDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(runtime.dispose);
  }

  Future<void> pumpHost(WidgetTester tester) async {
    runtime = makeRuntime();
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await runtime.start();
    await runtime.active.workspace.load();
    await tester.pumpWidget(AppHost(runtime: runtime));
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('sign-in')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-email')),
      'a@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('sign-in-password')),
      'pw',
    );
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('sign in: the dialog closes and the account workspace shows', (
    tester,
  ) async {
    await pumpHost(tester);
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    await signIn(tester);
    expect(find.byKey(const ValueKey('sign-in-dialog')), findsNothing);
    expect(runtime.active.userId, userA);
    expect(find.byKey(const ValueKey('sign-out')), findsOneWidget);
    // a new account is empty: nothing is created or imported automatically
    expect(find.byKey(const ValueKey('empty-account')), findsOneWidget);
    await shutDown(tester);
  });

  testWidgets('a failed sign-in leaves the dialog usable for a retry', (
    tester,
  ) async {
    await pumpHost(tester);
    api.signInFailures.add(const AuthNetworkFailure('timeout'));
    await signIn(tester);
    expect(find.byKey(const ValueKey('sign-in-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('sign-in-error')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sign-in-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sign-in-dialog')), findsNothing);
    expect(runtime.active.userId, userA);
    await shutDown(tester);
  });

  testWidgets('sign out and sign in again through the UI', (tester) async {
    await pumpHost(tester);
    await signIn(tester);
    await tester.tap(find.byKey(const ValueKey('sign-out')));
    await tester.pumpAndSettle();
    expect(runtime.active.userId, isNull);
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    await signIn(tester);
    expect(runtime.active.userId, userA);
    expect(find.byKey(const ValueKey('sign-in-dialog')), findsNothing);
    await shutDown(tester);
  });

  test('the import panel exists only for a signed-in account', () async {
    runtime = makeRuntime();
    await runtime.start();
    expect(runtime.importPanel(), isNull);
    await runtime.signIn('a@example.test', 'pw');
    expect(runtime.importPanel(), isA<ImportPanel>());
    await runtime.dispose();
  });
}
