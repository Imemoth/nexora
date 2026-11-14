import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/tasks/domain/calendar_date.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/domain/project.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:nexora/runtime/runtime_config.dart';
import 'package:nexora/runtime/sync_runtime.dart';

import '../support/fake_auth.dart';
import '../support/fake_sync_server.dart';
import '../support/reminder_support.dart';
import '../support/task_fixtures.dart';
import '../support/token_gate_transport.dart';

final class _Today implements Clock {
  @override
  CalendarDate today() => const CalendarDate(2026, 11, 14);
}

/// Reminders live in the database file of the active workspace: they follow the
/// account, never cross to another one, survive a restart and are never sent to
/// the server.
void main() {
  late Directory dir;
  late FakeAuthApi api;
  late InMemorySecureStore store;
  late FakeZoneClock zone;
  late FakeReminderNotifier notifier;
  late Map<String, FakeSyncServer> servers;
  final noon = DateTime.utc(2026, 11, 14, 17);
  var authClock = DateTime.utc(2026, 11, 14, 17);

  SyncRuntime build() {
    final sessions = SessionManager(
      api: api,
      store: store,
      now: () => authClock,
    );
    return SyncRuntime(
      sessions: sessions,
      paths: AccountPaths(dir),
      localDatabasePath: '${dir.path}${Platform.pathSeparator}nexora.db',
      config: RuntimeConfig.validate(
        'http://127.0.0.1:1',
        fakeJwt(sub: userA, expiresAt: DateTime.utc(2035), role: 'anon'),
      ),
      ids: RandomIdGenerator(),
      clock: _Today(),
      schedulerInterval: const Duration(hours: 1),
      autoSyncOnSignIn: false,
      sleep: (d) async {},
      reminderNotifier: notifier,
      reminderClock: zone,
      transportFactory: (c, token) {
        final user = sessionsUser(sessions);
        return TokenGate(servers.putIfAbsent(user, FakeSyncServer.new), token);
      },
    );
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nexora-remrt-');
    authClock = noon;
    api = FakeAuthApi(() => authClock);
    store = InMemorySecureStore();
    zone = FakeZoneClock(noon);
    notifier = FakeReminderNotifier();
    servers = {};
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // a handle may still be closing on Windows
    }
  });

  Future<void> addTask(SyncRuntime runtime, String id) async {
    await runtime.active.repository.saveProject(
      const Project(id: 'p1', name: 'P', position: 0),
    );
    await runtime.active.repository.saveTask(makeTask(id: id, title: 'T $id'));
  }

  test(
    'every workspace the runtime opens has its own reminder service',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      expect(runtime.active.reminders, isNotNull);
      final local = runtime.active.reminders;
      await runtime.signIn('a@example.test', 'pw');
      expect(runtime.active.reminders, isNotNull);
      expect(runtime.active.reminders, isNot(same(local)));
    },
  );

  test('reminders follow the account and never cross to another one', () async {
    final runtime = build();
    await runtime.start();
    addTearDown(runtime.dispose);

    await runtime.signIn('a@example.test', 'pw');
    await addTask(runtime, 'ta');
    runtime.active.reminders!.setReminder(
      'ta',
      const LocalWallTime(2026, 11, 14, 13, 0),
    );
    await runtime.signOut();
    expect(runtime.active.reminders!.reminderFor('ta'), isNull);

    await runtime.signIn('b@example.test', 'pw');
    expect(runtime.active.reminders!.reminderFor('ta'), isNull);
    await runtime.signOut();

    await runtime.signIn('a@example.test', 'pw');
    expect(runtime.active.reminders!.reminderFor('ta'), isNotNull);
  });

  test('a reminder survives a restart and fires once afterwards', () async {
    var runtime = build();
    await runtime.start();
    await runtime.signIn('a@example.test', 'pw');
    await addTask(runtime, 'ta');
    runtime.active.reminders!.setReminder(
      'ta',
      const LocalWallTime(2026, 11, 14, 13, 0),
    );
    await runtime.dispose();

    zone.now = noon.add(const Duration(hours: 2));
    runtime = build();
    addTearDown(runtime.dispose);
    await runtime.start();
    await runtime.active.reminders!.tick();
    await runtime.active.reminders!.tick();
    expect(notifier.shown.where((n) => n.taskId == 'ta'), hasLength(1));
  });

  test(
    'reminders are never synchronized: the server never sees them',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      await runtime.signIn('a@example.test', 'pw');
      await addTask(runtime, 'ta');
      runtime.active.reminders!.setReminder(
        'ta',
        const LocalWallTime(2026, 11, 14, 13, 0),
      );
      await runtime.syncNow();
      final server = servers[userA]!;
      expect(server.rows.keys, contains('task:ta'));
      for (final row in server.rows.values) {
        expect(row.toString(), isNot(contains('remind')));
      }
    },
  );

  test(
    'offline: reminders keep working with no session and no network',
    () async {
      final runtime = build();
      await runtime.start();
      addTearDown(runtime.dispose);
      await addTask(runtime, 'tl'); // signed out, local workspace
      runtime.active.reminders!.setReminder(
        'tl',
        const LocalWallTime(2026, 11, 14, 13, 0),
      );
      zone.now = noon.add(const Duration(hours: 1));
      await runtime.active.reminders!.tick();
      expect(notifier.shown, hasLength(1));
      expect(api.signIns + api.refreshes, 0);
    },
  );
}

String sessionsUser(SessionManager m) => m.userId ?? 'none';
