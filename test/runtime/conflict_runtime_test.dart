import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/conflicts.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/runtime/app_host.dart';
import 'package:nexora/runtime/runtime_config.dart';
import 'package:nexora/runtime/sync_runtime.dart';

import '../support/fake_auth.dart';
import '../support/fake_sync_server.dart';
import '../support/task_fixtures.dart';
import '../support/token_gate_transport.dart';

final class _FixedClock implements Clock {
  @override
  CalendarDate today() => const CalendarDate(2026, 11, 12);
}

/// The complete user path of the conflict screens through the real runtime, two
/// devices of one account and a fake server: detect, open from the status bar,
/// compare, decide, confirm, and watch both devices converge.
void main() {
  late Directory root;
  late Map<String, FakeSyncServer> servers;
  var installs = 0;
  var now = DateTime.utc(2026, 11, 12, 12);

  RuntimeConfig config() => RuntimeConfig.validate(
    'http://127.0.0.1:1',
    fakeJwt(sub: userA, expiresAt: DateTime.utc(2035), role: 'anon'),
  )!;

  /// One installation (its own folder and session store); [dir] and [store]
  /// reopen an existing one (an application restart).
  ({SyncRuntime runtime, Directory dir, InMemorySecureStore store}) install({
    Directory? dir,
    InMemorySecureStore? store,
    SyncTransport Function(SyncTransport inner)? wrap,
  }) {
    final folder =
        dir ??
        (Directory('${root.path}${Platform.pathSeparator}device${installs++}')
          ..createSync(recursive: true));
    final secrets = store ?? InMemorySecureStore();
    final sessions = SessionManager(
      api: FakeAuthApi(() => now),
      store: secrets,
      now: () => now,
    );
    final runtime = SyncRuntime(
      sessions: sessions,
      paths: AccountPaths(folder),
      localDatabasePath: '${folder.path}${Platform.pathSeparator}nexora.db',
      config: config(),
      ids: RandomIdGenerator(),
      clock: _FixedClock(),
      schedulerInterval: const Duration(hours: 1),
      autoSyncOnSignIn: false,
      sleep: (d) async {},
      transportFactory: (c, token) {
        final gate = TokenGate(
          servers.putIfAbsent(sessions.userId ?? 'none', FakeSyncServer.new),
          token,
        );
        return wrap == null ? gate : wrap(gate);
      },
    );
    return (runtime: runtime, dir: folder, store: secrets);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('nexora-confrt-');
    servers = {};
    installs = 0;
    now = DateTime.utc(2026, 11, 12, 12);
  });
  tearDown(() {
    try {
      root.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle may still be closing on Windows
    }
  });

  String title(SyncRuntime r, String id) =>
      r.active.db.raw.select('SELECT title FROM tasks WHERE id = ?', [
            id,
          ]).single['title']
          as String;

  /// Both devices signed in; the task exists on both; then the two devices edit
  /// the same title differently, A syncs first. Returns B (the one in conflict).
  Future<(SyncRuntime, SyncRuntime)> conflictOnB() async {
    final a = install().runtime;
    final b = install().runtime;
    await a.start();
    await b.start();
    await a.signIn('a@example.test', 'pw');
    await b.signIn('a@example.test', 'pw');
    await a.active.repository.saveProject(
      const Project(id: 'p1', name: 'Home', position: 0),
    );
    await a.active.repository.saveTask(
      makeTask(id: 't1', projectId: 'p1', title: 'Original'),
    );
    await a.syncNow();
    await b.syncNow();
    await a.active.repository.saveTask(
      makeTask(id: 't1', projectId: 'p1', title: 'CONFLICT-A'),
    );
    await b.active.repository.saveTask(
      makeTask(id: 't1', projectId: 'p1', title: 'CONFLICT-B'),
    );
    await a.syncNow();
    await b.syncNow();
    return (a, b);
  }

  test('no conflict panel while signed out', () async {
    final app = install().runtime;
    await app.start();
    addTearDown(app.dispose);
    expect(app.conflictPanel(), isNull);
  });

  test('the owner scenario: CONFLICT-A vs CONFLICT-B, keep mine, both devices converge', () async {
    final (a, b) = await conflictOnB();
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    expect((await b.syncNow()).openConflicts, 1);
    final panel = b.conflictPanel()!;
    final view = panel.load().single;
    expect(view.fields.single.local, const ConflictSide.value('CONFLICT-B'));
    expect(view.fields.single.server, const ConflictSide.value('CONFLICT-A'));

    final seen = <int>[];
    final sub = b.syncPanel().statuses.listen((s) => seen.add(s.openConflicts));
    addTearDown(sub.cancel);
    final outcome = await panel.resolve(view.id, ConflictChoice.keepLocal);
    expect(outcome.ok, isTrue);
    await b.syncNow();
    await a.syncNow();

    expect(panel.load(), isEmpty);
    expect(seen, contains(0)); // the status bar was told
    expect(title(a, 't1'), 'CONFLICT-B');
    expect(title(b, 't1'), 'CONFLICT-B');
    expect((await a.syncNow()).openConflicts, 0);
  });

  test('use server: both devices converge on the other value', () async {
    final (a, b) = await conflictOnB();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final panel = b.conflictPanel()!;

    final outcome = await panel.resolve(
      panel.load().single.id,
      ConflictChoice.useServer,
    );
    await b.syncNow();
    await a.syncNow();

    expect(outcome.ok, isTrue);
    expect(title(a, 't1'), 'CONFLICT-A');
    expect(title(b, 't1'), 'CONFLICT-A');
  });

  test(
    'offline attempt keeps the conflict; after a restart the retry succeeds',
    () async {
      FaultyTransport? faulty;
      final a = install().runtime;
      final deviceB = install(wrap: (inner) => faulty = FaultyTransport(inner));
      final b = deviceB.runtime;
      await a.start();
      await b.start();
      await a.signIn('a@example.test', 'pw');
      await b.signIn('a@example.test', 'pw');
      await a.active.repository.saveProject(
        const Project(id: 'p1', name: 'Home', position: 0),
      );
      await a.active.repository.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'Original'),
      );
      await a.syncNow();
      await b.syncNow();
      await a.active.repository.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'CONFLICT-A'),
      );
      await b.active.repository.saveTask(
        makeTask(id: 't1', projectId: 'p1', title: 'CONFLICT-B'),
      );
      await a.syncNow();
      await b.syncNow();
      addTearDown(a.dispose);
      final id = b.conflictPanel()!.load().single.id;
      final server = servers[userA]!;

      // The server cannot be reached while deciding: nothing changes.
      faulty!.before = (call) async {
        if (call == 'resolve') {
          throw const SyncNetworkFailure('offline');
        }
      };
      final failed = await b.conflictPanel()!.resolve(
        id,
        ConflictChoice.keepLocal,
      );
      expect(failed.kind, ConflictOutcomeKind.offline);
      expect(b.conflictPanel()!.load(), hasLength(1));
      expect(title(b, 't1'), 'CONFLICT-B');
      expect(server.conflicts.values.single['status'], 'open');

      // Restart: the conflict is restored from the local file.
      await b.dispose();
      final reopened = install(dir: deviceB.dir, store: deviceB.store);
      final b2 = reopened.runtime;
      addTearDown(b2.dispose);
      await b2.start();
      final restored = b2.conflictPanel()!.load();
      expect(restored.single.id, id);
      expect(
        restored.single.fields.single.server,
        const ConflictSide.value('CONFLICT-A'),
      );

      final outcome = await b2.conflictPanel()!.resolve(
        id,
        ConflictChoice.keepLocal,
      );
      expect(outcome.ok, isTrue);
      expect(server.rows['task:t1']!['title'], 'CONFLICT-B');
      expect(b2.conflictPanel()!.load(), isEmpty);
    },
  );

  testWidgets(
    'through the real window: open from the status bar, compare, decide, confirm, converge',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late SyncRuntime a;
      late SyncRuntime b;
      // Everything that awaits the runtime outside the widgets runs in the
      // real zone, where the runtime was built.
      await tester.runAsync(() async {
        final pair = await conflictOnB();
        a = pair.$1;
        b = pair.$2;
        await b.active.workspace.load();
      });
      await tester.pumpWidget(AppHost(runtime: b));
      await tester.pumpAndSettle();

      // 1. The status bar offers the conflict as a control.
      expect(find.text('1 conflict needs your decision'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sync-conflicts')));
      await tester.pumpAndSettle();

      // 2. Both values are there, in words.
      expect(find.byKey(const ValueKey('conflict-dialog')), findsOneWidget);
      expect(find.text('CONFLICT-B'), findsWidgets);
      expect(
        find.byKey(const ValueKey('conflict-local-title')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('conflict-local-title')))
            .data,
        'CONFLICT-B',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('conflict-server-title')))
            .data,
        'CONFLICT-A',
      );

      // 3 and 4. Choose and confirm.
      await tester.tap(find.byKey(const ValueKey('choice-keepLocal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('conflict-confirm-yes')));
      await tester.pumpAndSettle();

      // 5. The conflict is gone, in the dialog and in the status bar. (The
      // runtime's own event loop turn runs in the real zone.)
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('conflict-none-left')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('conflict-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sync-conflicts')), findsNothing);

      // 6. Both devices converge on the chosen value.
      await tester.runAsync(() async {
        await b.syncNow();
        await a.syncNow();
      });
      expect(title(a, 't1'), 'CONFLICT-B');
      expect(title(b, 't1'), 'CONFLICT-B');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await b.dispose();
        await a.dispose();
      });
    },
  );
}
