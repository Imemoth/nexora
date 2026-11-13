import 'dart:async';
import 'dart:convert';

import 'auth_api.dart';
import 'auth_diagnostics.dart';
import 'auth_failure.dart';
import 'auth_session.dart';
import 'secure_store.dart';

/// Where authentication stands.
enum AuthPhase {
  /// No account. The local workspace works; nothing synchronizes.
  signedOut,

  /// A session exists. It may be offline: the stored session is used until the
  /// service can be reached.
  signedIn,

  /// The service refused the stored session (revoked, expired for good, user
  /// deleted). The account's local data stays on this device and keeps working;
  /// synchronization is paused until the user signs in again.
  reauthRequired,
}

/// The reason behind the last change, for a message the user can act on.
enum AuthReason {
  none,
  userSignedOut,
  sessionRevoked,
  anonymousRejected,
  storageUnreadable,
}

/// An immutable snapshot for the UI and the sync runtime.
final class AuthState {
  const AuthState({
    required this.phase,
    this.session,
    this.userId,
    this.reason = AuthReason.none,
  });

  final AuthPhase phase;
  final AuthSession? session;

  /// The account this device last used, kept even when the tokens are gone so
  /// that the account's local database can still be opened offline.
  final String? userId;
  final AuthReason reason;

  String? get email => session?.email;
}

/// Sign-in, restoration, refresh and sign-out, with strict rules about data:
/// * Restoring a session never needs the network.
/// * An anonymous identity is never accepted.
/// * Refresh is single-flight, and the new refresh token is stored before it is
///   used (a refresh token can be used once).
/// * A refused refresh clears the tokens but never touches local data, and the
///   account the device used stays known ([AuthState.userId]).
/// * Sign-out always clears the tokens, even when the server cannot be reached.
final class SessionManager {
  SessionManager({
    required AuthApi api,
    required SecureStore store,
    DateTime Function()? now,
    this.refreshMargin = const Duration(seconds: 60),
    this._log = const NullAuthLog(),
  }) : _authApi = api,
       _secrets = store,
       _now = now ?? (() => DateTime.now().toUtc());

  static const String _sessionKey = 'session';
  static const String _userKey = 'last_user';

  final AuthApi _authApi;
  final SecureStore _secrets;
  final DateTime Function() _now;
  final AuthLog _log;
  final Duration refreshMargin;

  AuthState _state = const AuthState(phase: AuthPhase.signedOut);
  Future<AuthSession?>? _refreshing;
  final StreamController<AuthState> _controller =
      StreamController<AuthState>.broadcast();

  AuthState get state => _state;
  Stream<AuthState> get states => _controller.stream;

  /// The signed-in account, or null.
  String? get userId =>
      _state.phase == AuthPhase.signedIn ? _state.session?.userId : null;

  void _set(AuthState next) {
    _state = next;
    if (!_controller.isClosed) {
      _controller.add(next);
    }
  }

  Future<void> dispose() => _controller.close();

  // ----------------------------------------------------------- restore

  /// Reads the stored session. No network. A missing, damaged, unreadable or
  /// anonymous record becomes "signed out" (the broken record is removed; it holds
  /// only tokens, never user data).
  Future<AuthState> restore() async {
    String? raw;
    String? hint;
    _log.log('restore.start');
    try {
      raw = await _secrets.read(_sessionKey);
      hint = await _secrets.read(_userKey);
    } on Object {
      // A protected store that fails in any way must not stop the application
      // from starting: the session is treated as unreadable (local data stays).
      _log.log('restore.unreadable');
      await _forgetTokens();
      _set(
        const AuthState(
          phase: AuthPhase.signedOut,
          reason: AuthReason.storageUnreadable,
        ),
      );
      return _state;
    }
    if (raw != null) {
      AuthSession? session;
      try {
        session = AuthSession.fromJson(jsonDecode(raw));
      } on FormatException {
        session = null;
      }
      if (session != null && session.isAnonymous) {
        await _forgetTokens();
        await _safeDelete(_userKey);
        _set(
          const AuthState(
            phase: AuthPhase.signedOut,
            reason: AuthReason.anonymousRejected,
          ),
        );
        return _state;
      }
      if (session != null) {
        _set(
          AuthState(
            phase: AuthPhase.signedIn,
            session: session,
            userId: session.userId,
          ),
        );
        return _state;
      }
      await _forgetTokens();
    }
    if (hint != null && hint.isNotEmpty) {
      _set(
        AuthState(
          phase: AuthPhase.reauthRequired,
          userId: hint,
          reason: AuthReason.sessionRevoked,
        ),
      );
    } else {
      _set(const AuthState(phase: AuthPhase.signedOut));
    }
    return _state;
  }

  // ----------------------------------------------------------- sign in

  /// Signs in with email and password. Throws an [AuthFailure]; the state does not
  /// change on failure. A different account replaces the current one: the former
  /// account's local database is untouched and is not reachable from the new one.
  Future<AuthState> signIn(String email, String password) async {
    _log.log('signin.api.start');
    final session = await _authApi.signInWithPassword(email.trim(), password);
    _log.log('signin.api.ok');
    if (session.isAnonymous) {
      try {
        await _authApi.signOut(session.accessToken);
      } on AuthFailure {
        // best effort
      }
      throw const AuthAnonymousRejected();
    }
    // The server accepted the credentials. Saving the session in the protected
    // store is bounded and must not strand the user: when it fails, the session
    // is kept in memory for this run and the UI tells the user it will not be
    // remembered (the same rule as for a refreshed session).
    var reason = AuthReason.none;
    _log.log('signin.persist.start');
    try {
      await _persist(session);
      _log.log('signin.persist.ok');
    } on AuthFailure catch (error) {
      _log.log('signin.persist.failed', {'code': error.message});
      reason = AuthReason.storageUnreadable;
    } on Object catch (error) {
      _log.log('signin.persist.failed', {'type': error.runtimeType});
      reason = AuthReason.storageUnreadable;
    }
    _set(
      AuthState(
        phase: AuthPhase.signedIn,
        session: session,
        userId: session.userId,
        reason: reason,
      ),
    );
    _log.log('signin.state.set', {'phase': 'signedIn'});
    return _state;
  }

  /// Forgets the session of this run without contacting the server (used when
  /// the account's local workspace could not be opened). Local data is never
  /// touched; the user can retry the sign-in.
  Future<void> abandonSession() async {
    await _forgetTokens();
    await _safeDelete(_userKey);
    _set(const AuthState(phase: AuthPhase.signedOut));
  }

  // ------------------------------------------------------------ tokens

  /// A usable access token, refreshing first when the current one is about to
  /// expire. Null when there is no session. Throws [AuthNetworkFailure] when a
  /// refresh is needed but the service cannot be reached and the token has
  /// expired (a token that is still valid keeps being used offline).
  Future<String?> accessToken() async {
    final session = _state.session;
    if (_state.phase != AuthPhase.signedIn || session == null) {
      return null;
    }
    if (session.isFresh(_now(), refreshMargin)) {
      return session.accessToken;
    }
    try {
      final refreshed = await _refresh();
      return refreshed?.accessToken;
    } on AuthNetworkFailure {
      final current = _state.session;
      if (current != null && !current.isExpired(_now())) {
        return current.accessToken;
      }
      rethrow;
    } on AuthRateLimited {
      final current = _state.session;
      if (current != null && !current.isExpired(_now())) {
        return current.accessToken;
      }
      rethrow;
    }
  }

  /// The server rejected the access token although it looked valid (clock skew,
  /// rotated signing key, revoked session). Refresh once. True when a new access
  /// token is ready.
  Future<bool> refreshAfterRejection() async {
    if (_state.phase != AuthPhase.signedIn) {
      return false;
    }
    try {
      final refreshed = await _refresh();
      return refreshed != null;
    } on AuthFailure {
      return false;
    }
  }

  Future<AuthSession?> _refresh() {
    final running = _refreshing;
    if (running != null) {
      return running;
    }
    final future = _doRefresh().whenComplete(() => _refreshing = null);
    _refreshing = future;
    return future;
  }

  Future<AuthSession?> _doRefresh() async {
    final before = _state.session;
    if (before == null) {
      return null;
    }
    final AuthSession next;
    try {
      next = await _authApi.refresh(before.refreshToken);
    } on AuthSessionRevoked {
      await _forgetTokens();
      _set(
        AuthState(
          phase: AuthPhase.reauthRequired,
          userId: before.userId,
          reason: AuthReason.sessionRevoked,
        ),
      );
      return null;
    }
    if (next.isAnonymous || next.userId != before.userId) {
      // A refresh must never change the account or turn anonymous.
      await _forgetTokens();
      _set(
        AuthState(
          phase: AuthPhase.reauthRequired,
          userId: before.userId,
          reason: next.isAnonymous
              ? AuthReason.anonymousRejected
              : AuthReason.sessionRevoked,
        ),
      );
      return null;
    }
    // Keep working in memory even if the protected store fails; the old refresh
    // token is already consumed, so the new one must not be lost silently.
    try {
      await _persist(next);
    } on AuthStorageFailure {
      _set(
        AuthState(
          phase: AuthPhase.signedIn,
          session: next,
          userId: next.userId,
          reason: AuthReason.storageUnreadable,
        ),
      );
      return next;
    }
    _set(
      AuthState(phase: AuthPhase.signedIn, session: next, userId: next.userId),
    );
    return next;
  }

  // ---------------------------------------------------------- sign out

  /// Ends the session. The tokens are always forgotten, even offline. The
  /// account's local database stays on disk untouched.
  Future<AuthState> signOut() async {
    final session = _state.session;
    if (session != null) {
      try {
        await _authApi.signOut(session.accessToken);
      } on AuthFailure {
        // The server will expire the session by itself.
      }
    }
    await _forgetTokens();
    await _safeDelete(_userKey);
    _set(
      const AuthState(
        phase: AuthPhase.signedOut,
        reason: AuthReason.userSignedOut,
      ),
    );
    return _state;
  }

  // ------------------------------------------------------------ helpers

  Future<void> _persist(AuthSession session) async {
    await _secrets.write(_sessionKey, jsonEncode(session.toJson()));
    await _secrets.write(_userKey, session.userId);
  }

  Future<void> _forgetTokens() => _safeDelete(_sessionKey);

  Future<void> _safeDelete(String key) async {
    try {
      await _secrets.delete(key);
    } on Object {
      // nothing more can be done; the value is unreadable anyway
    }
  }
}
