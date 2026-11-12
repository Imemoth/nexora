import 'dart:async';
import 'dart:io';

import 'package:nexora/app/account_panel.dart';
import 'package:nexora/app/sync_panel.dart';
import 'package:nexora/core/ids/id_generator.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/authenticated_transport.dart';
import 'package:nexora/features/sync/supabase_sync_transport.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_status.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/application/repository_exception.dart';
import 'package:nexora/features/tasks/application/task_workspace.dart';
import 'package:nexora/features/tasks/domain/clock.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/local_storage.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/pull_applier.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';
import 'package:nexora/features/tasks/presentation/strings/app_strings.dart';

import 'runtime_config.dart';
import 'session_token_source.dart';
import 'sync_scheduler.dart';

/// Builds the real transport for a signed-in account. Replaced in tests.
typedef TransportFactory = SyncTransport Function(
  RuntimeConfig config,
  Future<String?> Function() accessToken,
);

SyncTransport _httpTransport(
  RuntimeConfig config,
  Future<String?> Function() accessToken,
) => SupabaseSyncTransport(
  baseUrl: config.supabaseUrl,
  anonKey: config.anonKey,
  accessToken: accessToken,
);

/// The workspace the user is looking at: the local workspace when signed out, or
/// one account's own database. Replaced as a unit on sign-in, sign-out and
/// account switch; a database is never reused for another account.
final class ActiveWorkspace {
  ActiveWorkspace._({
    required this.userId,
    required this.db,
    required this.workspace,
    required this.repository,
  });

  /// The account this workspace belongs to; null for the local workspace.
  final String? userId;
  final LocalDatabase db;
  final TaskWorkspace workspace;
  final SqliteTaskRepository repository;

  SyncEngine? engine;
  SyncStateStore? state;
  SyncScheduler? scheduler;
  bool refreshPending = false;
  StreamSubscription<Object?>? _watch;

  void close() {
    scheduler?.stop();
    _watch?.cancel();
    workspace.dispose();
    db.close();
  }
}

/// Connects authentication, per-account storage and the sync engine.
///
/// With the flag off this class is never constructed. With it on it still does
/// nothing network-related until an account is signed in: a signed-out runtime
/// has no engine, no scheduler and no transport.
final class SyncRuntime {
  SyncRuntime({
    required this.sessions,
    required this.paths,
    required this.localDatabasePath,
    required this.config,
    required this.ids,
    required this.clock,
    TransportFactory? transportFactory,
    this.schedulerInterval = const Duration(seconds: 60),
    SyncEngineConfig engineConfig = const SyncEngineConfig(),
    Future<void> Function(Duration)? sleep,
    SyncHook? hook,
    this.autoSyncOnSignIn = true,
  }) : _transportFactory = transportFactory ?? _httpTransport,
       _engineSettings = engineConfig,
       _sleepFn = sleep,
       _syncHook = hook;

  final SessionManager sessions;
  final AccountPaths paths;
  final String localDatabasePath;

  /// Null when the project settings are missing or unacceptable: the runtime
  /// then never builds an engine.
  final RuntimeConfig? config;
  final IdGenerator ids;
  final Clock clock;
  final Duration schedulerInterval;

  /// Start a cycle right after a successful sign-in (tests turn it off to
  /// control timing).
  final bool autoSyncOnSignIn;
  final TransportFactory _transportFactory;
  final SyncEngineConfig _engineSettings;
  final Future<void> Function(Duration)? _sleepFn;
  final SyncHook? _syncHook;

  ActiveWorkspace? _active;
  StreamSubscription<AuthState>? _authWatch;
  final StreamController<ActiveWorkspace> _workspaceChanges =
      StreamController<ActiveWorkspace>.broadcast();
  final StreamController<SyncStatus> _syncStatuses =
      StreamController<SyncStatus>.broadcast();
  final StreamController<AccountView> _accountViews =
      StreamController<AccountView>.broadcast();
  SyncStatus _lastStatus = const SyncStatus(phase: SyncPhase.disabled);
  Future<void> _activation = Future<void>.value();

  ActiveWorkspace get active => _active!;
  Stream<ActiveWorkspace> get workspaceChanges => _workspaceChanges.stream;

  // --------------------------------------------------------------- start

  /// Restores the session (no network) and opens the matching workspace.
  Future<ActiveWorkspace> start() async {
    await sessions.restore();
    await _activate();
    _authWatch ??= sessions.states.listen((_) => _activate());
    return _active!;
  }

  Future<void> dispose() async {
    await _authWatch?.cancel();
    _active?.close();
    _active = null;
    await sessions.dispose();
    await _workspaceChanges.close();
    await _syncStatuses.close();
    await _accountViews.close();
  }

  // ------------------------------------------------------------- panels

  AccountPanel accountPanel() => AccountPanel(
    initial: _accountView(),
    views: _accountViews.stream,
    signIn: signIn,
    signOut: signOut,
  );

  SyncPanel syncPanel() => SyncPanel(
    initial: _lastStatus,
    statuses: _syncStatuses.stream,
    syncNow: () async {
      await syncNow();
    },
  );

  AccountView _accountView() {
    final state = sessions.state;
    return AccountView(
      phase: switch (state.phase) {
        AuthPhase.signedOut => AccountPhase.signedOut,
        AuthPhase.signedIn => AccountPhase.signedIn,
        AuthPhase.reauthRequired => AccountPhase.reauthRequired,
      },
      email: state.email,
      notice: switch (state.reason) {
        AuthReason.none => AccountNotice.none,
        AuthReason.userSignedOut => AccountNotice.signedOut,
        AuthReason.sessionRevoked => AccountNotice.sessionExpired,
        AuthReason.anonymousRejected => AccountNotice.anonymousRejected,
        AuthReason.storageUnreadable => AccountNotice.storageProblem,
      },
    );
  }

  // ------------------------------------------------------------ commands

  Future<SignInOutcome> signIn(String email, String password) async {
    try {
      await sessions.signIn(email, password);
      await _activate();
      if (autoSyncOnSignIn) {
        unawaited(syncNow().then<void>((_) {}, onError: (Object _) {}));
      }
      return SignInOutcome.success;
    } on AuthInvalidCredentials {
      return SignInOutcome.invalidCredentials;
    } on AuthUnconfirmed {
      return SignInOutcome.unconfirmed;
    } on AuthAnonymousRejected {
      return SignInOutcome.anonymousRejected;
    } on AuthNetworkFailure {
      return SignInOutcome.offline;
    } on AuthRateLimited {
      return SignInOutcome.rateLimited;
    } on AuthFailure {
      return SignInOutcome.failed;
    }
  }

  Future<void> signOut() async {
    await sessions.signOut();
    await _activate();
  }

  /// The manual "Sync now" action. Does nothing (and sends nothing) without an
  /// engine, that is without a signed-in, configured account.
  Future<SyncStatus> syncNow() async {
    await _activation;
    final current = _active;
    final engine = current?.engine;
    if (current == null || engine == null) {
      return _lastStatus;
    }
    final scheduler = current.scheduler;
    if (scheduler != null) {
      await scheduler.kick();
    } else {
      await _runCycle(current);
    }
    // The engine's own status is the truth; the broadcast stream delivers later.
    _lastStatus = engine.status;
    return engine.status;
  }

  // ---------------------------------------------------------- activation

  Future<void> _activate() {
    _activation = _activation.then((_) => _doActivate());
    return _activation;
  }

  Future<void> _doActivate() async {
    final auth = sessions.state;
    final targetUser = auth.phase == AuthPhase.signedOut ? null : auth.userId;
    var current = _active;
    if (current == null || current.userId != targetUser) {
      current?.close();
      current = _open(targetUser);
      _active = current;
      _workspaceChanges.add(current);
    }
    _configureEngine(current, auth);
    _emitAccount();
  }

  ActiveWorkspace _open(String? userId) {
    final String path;
    if (userId == null) {
      path = localDatabasePath;
    } else {
      final file = paths.databaseFor(userId);
      path = file.path;
    }
    ensureParentFolder(path);
    final db = LocalDatabase.open(path);
    OutboxStore(db, ids: ids).recoverInFlight();
    final repository = SqliteTaskRepository(
      db,
      ownerId: ownerIdOf(db, ids),
      ids: ids,
    );
    final workspace = TaskWorkspace(
      repository: repository,
      clock: clock,
      ids: ids,
    );
    final active = ActiveWorkspace._(
      userId: userId,
      db: db,
      workspace: workspace,
      repository: repository,
    );
    active._watch = workspace.states.listen((state) {
      if (active.refreshPending && state.draft == null) {
        active.refreshPending = false;
        unawaited(workspace.refresh());
      }
    });
    return active;
  }

  void _configureEngine(ActiveWorkspace current, AuthState auth) {
    final wanted =
        auth.phase == AuthPhase.signedIn &&
        auth.session != null &&
        config != null &&
        current.userId == auth.userId;
    if (!wanted) {
      current.scheduler?.stop();
      current.scheduler = null;
      current.engine = null;
      current.state = null;
      _setStatus(
        SyncStatus(
          phase: auth.phase == AuthPhase.signedOut
              ? (config == null ? SyncPhase.disabled : SyncPhase.authRequired)
              : SyncPhase.authRequired,
          code: auth.phase == AuthPhase.reauthRequired
              ? 'reauth'
              : (config == null ? 'not_configured' : 'signed_out'),
          pending: _pendingOf(current),
        ),
      );
      return;
    }
    if (current.engine != null) {
      return;
    }
    final tokens = SessionTokenSource(sessions);
    final transport = AuthenticatedTransport(
      inner: _transportFactory(config!, tokens.accessToken),
      tokens: tokens,
      boundUserId: current.userId!,
    );
    final outbox = OutboxStore(current.db, ids: ids);
    final state = SyncStateStore(current.db);
    final engine = SyncEngine(
      transport: transport,
      outbox: outbox,
      state: state,
      pull: PullApplier(current.db),
      userId: () async => sessions.userId,
      ids: ids,
      enabled: true,
      config: _engineSettings,
      sleep: _sleepFn,
      hook: _syncHook,
    );
    current.engine = engine;
    current.state = state;
    engine.statuses.listen(_setStatus);
    current.scheduler = SyncScheduler(
      run: () => _runCycle(current),
      interval: schedulerInterval,
    )..start();
    _setStatus(engine.status);
  }

  int _pendingOf(ActiveWorkspace current) {
    try {
      return SyncStateStore(current.db).counts().pending;
    } on RepositoryException {
      return 0;
    }
  }

  Future<void> _runCycle(ActiveWorkspace current) async {
    final engine = current.engine;
    if (engine == null || !identical(current, _active)) {
      return;
    }
    final result = await engine.runWithRetry();
    if (!identical(current, _active)) {
      return;
    }
    if (result.phase == SyncPhase.idle) {
      await _afterCycle(current, engine);
    }
  }

  Future<void> _afterCycle(ActiveWorkspace current, SyncEngine engine) async {
    // A fresh account with nothing on the server gets its default project; an
    // account that already has projects keeps exactly those.
    final created = await current.repository.ensureDefaultProject(
      AppStrings.defaultProjectName,
    );
    if (created != null) {
      await engine.syncNow();
    }
    if (!await current.workspace.refresh()) {
      current.refreshPending = true;
    }
  }

  void _setStatus(SyncStatus status) {
    _lastStatus = status;
    if (!_syncStatuses.isClosed) {
      _syncStatuses.add(status);
    }
  }

  void _emitAccount() {
    if (!_accountViews.isClosed) {
      _accountViews.add(_accountView());
    }
  }

  /// For tests: the database folder of an account.
  Directory accountFolder(String userId) => paths.databaseFor(userId).parent;
}
