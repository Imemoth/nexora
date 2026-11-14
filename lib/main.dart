import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nexora/app/nexora_app.dart';
import 'package:nexora/app/startup_error_app.dart';
import 'package:nexora/app/system_clock.dart';
import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_diagnostics.dart';
import 'package:nexora/features/auth/windows_secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/sync_feature.dart';
import 'package:nexora/features/tasks/application/demo_data.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_storage.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';
import 'package:nexora/features/tasks/presentation/tasks_notifier.dart';
import 'package:nexora/runtime/app_host.dart';
import 'package:nexora/runtime/auth_selftest.dart';
import 'package:nexora/runtime/runtime_config.dart';
import 'package:nexora/runtime/sync_runtime.dart';
import 'package:nexora/features/tasks/application/reminder_service.dart';
import 'package:nexora/features/tasks/data/reminder_store.dart';
import 'package:nexora/features/tasks/domain/reminder.dart';
import 'package:nexora/features/tasks/presentation/strings/reminder_strings.dart';
import 'package:nexora/platform/desktop_integration.dart';

/// Phase 2A wiring: a durable local SQLite workspace.
///
/// The workspace opens (and migrates) the database, then loads what is stored.
/// Demo data is written only when `--demo` is passed, and only into a database
/// that never had demo data. An existing database is never overwritten. If the
/// database cannot be opened, the app shows an actionable message and changes
/// nothing.
Future<void> main(List<String> args) async {
  const clock = SystemClock();
  final ids = RandomIdGenerator();
  final desktop = WindowsDesktopIntegration.forPlatform();
  if (syncFeatureEnabled) {
    // Development self-test of the sign-in lifecycle inside the real executable
    // (no UI, no network); see lib/runtime/auth_selftest.dart.
    final selfTest =
        Platform.environment['NEXORA_AUTH_SELFTEST'] ??
        args
            .where((a) => a.startsWith('--auth-selftest='))
            .map((a) => a.substring('--auth-selftest='.length))
            .firstOrNull;
    if (selfTest != null && selfTest.isNotEmpty) {
      exit(await runAuthSelfTest(selfTest));
    }
    final started = await _startWithSync(ids, desktop);
    if (started) {
      return;
    }
  }
  try {
    final path = localDatabasePath(Platform.environment);
    ensureParentFolder(path);
    final db = LocalDatabase.open(path);
    // Crash recovery: an operation left in flight by an earlier run returns to
    // pending (the server replays by operation id). Nothing is sent: sync is off.
    OutboxStore(db, ids: ids).recoverInFlight();
    final repository = SqliteTaskRepository(
      db,
      ownerId: ownerIdOf(db, ids),
      ids: ids,
    );
    if (args.contains('--demo')) {
      final demo = buildDemoData(clock.today());
      await repository.seedDemoData(projects: demo.projects, tasks: demo.tasks);
    }
    await repository.ensureDefaultProject(AppStrings.defaultProjectName);
    final workspace = TaskWorkspace(
      repository: repository,
      clock: clock,
      ids: ids,
    );
    await workspace.load();
    final reminders = ReminderService(
      store: ReminderStore(db),
      clock: const SystemReminderClock(),
      notifier: desktop,
      texts: ReminderStrings.notificationTexts,
    );
    unawaited(reminders.start().catchError((Object _) {}));
    runApp(
      NexoraApp(
        notifier: TasksNotifier(workspace),
        desktop: desktop,
        reminders: reminders,
      ),
    );
  } on RepositoryException {
    runApp(const StartupErrorApp(message: AppStrings.errorDatabaseOpen));
  }
}

/// The synchronization build (`--dart-define=NEXORA_SYNC=true`). Without project
/// settings no account can sign in, nothing is sent, and the local workspace
/// opens as usual (returns false so the default start runs).
Future<bool> _startWithSync(
  RandomIdGenerator ids,
  DesktopIntegration desktop,
) async {
  final config = RuntimeConfig.load(Platform.environment);
  if (config == null) {
    return false;
  }
  try {
    final path = localDatabasePath(Platform.environment);
    final root = File(path).parent;
    // Development diagnostics of the sign-in lifecycle (step names and timings,
    // never passwords or tokens): <data folder>\diagnostics\signin.log
    final log = FileAuthLog(
      File(
        '${root.path}${Platform.pathSeparator}diagnostics${Platform.pathSeparator}signin.log',
      ),
    );
    log.log('app.start', {'sync': true});
    final runtime = SyncRuntime(
      log: log,
      sessions: SessionManager(
        log: log,
        api: SupabaseAuthApi(
          baseUrl: config.supabaseUrl,
          anonKey: config.anonKey,
        ),
        store: createWindowsSecureStore(
          Directory('${root.path}${Platform.pathSeparator}session'),
          log: log,
        ),
      ),
      paths: AccountPaths(root),
      localDatabasePath: path,
      config: config,
      ids: ids,
      clock: const SystemClock(),
      reminderNotifier: desktop,
    );
    final active = await runtime.start();
    if (active.userId == null) {
      await active.repository.ensureDefaultProject(
        AppStrings.defaultProjectName,
      );
    }
    await active.workspace.load();
    runApp(AppHost(runtime: runtime, desktop: desktop));
    return true;
  } on RepositoryException {
    runApp(const StartupErrorApp(message: AppStrings.errorDatabaseOpen));
    return true;
  }
}
