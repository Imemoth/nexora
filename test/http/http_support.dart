import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nexora/core/ids/random_id_generator.dart';
import 'package:nexora/features/auth/auth_api.dart';
import 'package:nexora/features/auth/auth_session.dart';
import 'package:nexora/features/auth/secure_store.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/authenticated_transport.dart';
import 'package:nexora/features/sync/supabase_sync_transport.dart';
import 'package:nexora/features/sync/sync_engine.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/tasks/data/local_database.dart';
import 'package:nexora/features/tasks/data/outbox_store.dart';
import 'package:nexora/features/tasks/data/pull_applier.dart';
import 'package:nexora/features/tasks/data/sqlite_task_repository.dart';
import 'package:nexora/features/tasks/data/sync_state_store.dart';
import 'package:nexora/runtime/session_token_source.dart';

import '../support/sha256.dart';

/// A disposable local Supabase stack (the Supabase CLI's `supabase start`: Kong,
/// GoTrue and PostgREST on a PostgreSQL 17 database that carries the real S1-S4
/// migrations). Nothing here talks to a hosted project. The tests are skipped
/// unless `NEXORA_HTTP_URL` is set, which only the http-integration workflow does.
final class Stack {
  Stack._(this.url, this.anonKey, this.serviceKey, this.jwtSecret);

  final String url;
  final String anonKey;

  /// Used only by the test harness (admin API, reading rows past RLS). The
  /// application code under test never receives it.
  final String serviceKey;
  final String jwtSecret;

  static Stack? fromEnvironment() {
    final env = Platform.environment;
    final url = env['NEXORA_HTTP_URL'];
    if (url == null || url.isEmpty) {
      return null;
    }
    return Stack._(
      url,
      env['NEXORA_HTTP_ANON_KEY']!,
      env['NEXORA_HTTP_SERVICE_KEY']!,
      env['NEXORA_HTTP_JWT_SECRET']!,
    );
  }

  final HttpClient _http = HttpClient();

  Future<({int status, Object? body})> request(
    String method,
    String path, {
    String? token,
    String? apikey,
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final request = await _http.openUrl(method, Uri.parse('$url$path'));
    request.headers.set('apikey', apikey ?? anonKey);
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = text;
    }
    return (status: response.statusCode, body: decoded);
  }

  /// Registers a confirmed email/password user and returns its id.
  Future<({String id, String email, String password})> signUp([
    String? tag,
  ]) async {
    final suffix = RandomIdGenerator().nextId().substring(0, 8);
    final email = 'nx-${tag ?? 'user'}-$suffix@example.test';
    const password = 'Test-passw0rd!';
    final r = await request(
      'POST',
      '/auth/v1/signup',
      body: {'email': email, 'password': password},
    );
    if (r.status != 200) {
      throw StateError('signup failed: ${r.status} ${r.body}');
    }
    final user = (r.body! as Map)['user'] as Map? ?? r.body! as Map;
    return (id: (user['id'] as String).toLowerCase(), email: email, password: password);
  }

  /// An anonymous GoTrue session (needs `enable_anonymous_sign_ins`).
  Future<AuthSession> anonymousSession() async {
    final r = await request('POST', '/auth/v1/signup', body: {});
    if (r.status != 200) {
      throw StateError('anonymous sign-in failed: ${r.status} ${r.body}');
    }
    final b = r.body! as Map;
    final user = b['user'] as Map;
    return AuthSession(
      accessToken: b['access_token'] as String,
      refreshToken: b['refresh_token'] as String,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      userId: (user['id'] as String).toLowerCase(),
      email: null,
      isAnonymous: user['is_anonymous'] == true,
    );
  }

  Future<void> adminDeleteUser(String id) async {
    final r = await request(
      'DELETE',
      '/auth/v1/admin/users/$id',
      token: serviceKey,
      apikey: serviceKey,
    );
    if (r.status != 200) {
      throw StateError('admin delete failed: ${r.status} ${r.body}');
    }
  }

  /// Rows read past RLS with the service-role key (harness only).
  Future<List<Map<String, Object?>>> adminRows(String table, [String query = '']) async {
    final r = await request(
      'GET',
      '/rest/v1/$table?$query',
      token: serviceKey,
      apikey: serviceKey,
    );
    if (r.status != 200) {
      throw StateError('adminRows $table: ${r.status} ${r.body}');
    }
    return [for (final row in r.body! as List) Map<String, Object?>.from(row as Map)];
  }

  /// A correctly signed HS256 token with the stack's own secret: the one thing a
  /// real client cannot do, used to produce an expired token the server must
  /// recognise as expired (not merely malformed).
  String mintToken({
    required String sub,
    required DateTime expiresAt,
    String role = 'authenticated',
  }) {
    String b64(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    final head = b64({'alg': 'HS256', 'typ': 'JWT'});
    final payload = b64({
      'sub': sub,
      'role': role,
      'aud': 'authenticated',
      'iss': '$url/auth/v1',
      'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
      'iat': expiresAt.millisecondsSinceEpoch ~/ 1000 - 3600,
      'is_anonymous': false,
    });
    final signature = base64Url
        .encode(hmacSha256(utf8.encode(jwtSecret), utf8.encode('$head.$payload')))
        .replaceAll('=', '');
    return '$head.$payload.$signature';
  }

  void close() => _http.close(force: true);
}

/// A signed-in device: the real authentication client, the real HTTP transport
/// and the real engine over a real SQLite file.
final class Device {
  Device._({
    required this.stack,
    required this.path,
    required this.db,
    required this.repo,
    required this.outbox,
    required this.state,
    required this.sessions,
    required this.store,
    required this.engine,
    required this.transport,
  });

  final Stack stack;
  final String path;
  final LocalDatabase db;
  final SqliteTaskRepository repo;
  final OutboxStore outbox;
  final SyncStateStore state;
  final SessionManager sessions;
  final InMemorySecureStore store;
  final SyncEngine engine;
  final SyncTransport transport;

  String get deviceId => outbox.deviceId();

  List<Map<String, Object?>> rows(String sql, [List<Object?> params = const []]) => [
    for (final r in db.raw.select(sql, params)) {for (final k in r.keys) k: r[k]},
  ];

  /// Opens a database file, signs in, and builds the engine. [wrap] can decorate
  /// the real HTTP transport (fault injection at the HTTP boundary).
  static Future<Device> open(
    Stack stack,
    Directory dir,
    String email,
    String password, {
    String? path,
    SyncTransport Function(SyncTransport inner)? wrap,
    SecureStore? store,
    bool signIn = true,
  }) async {
    final file = path ?? '${dir.path}${Platform.pathSeparator}d${RandomIdGenerator().nextId().substring(0, 6)}.db';
    final db = LocalDatabase.open(file);
    final secure = (store as InMemorySecureStore?) ?? InMemorySecureStore();
    final sessions = SessionManager(
      api: SupabaseAuthApi(baseUrl: stack.url, anonKey: stack.anonKey),
      store: secure,
    );
    if (signIn) {
      await sessions.signIn(email, password);
    } else {
      await sessions.restore();
    }
    final tokens = SessionTokenSource(sessions);
    final real = SupabaseSyncTransport(
      baseUrl: stack.url,
      anonKey: stack.anonKey,
      accessToken: tokens.accessToken,
    );
    SyncTransport inner = real;
    if (wrap != null) {
      inner = wrap(real);
    }
    final bound = sessions.state.userId ?? sessions.state.session!.userId;
    final transport = AuthenticatedTransport(
      inner: inner,
      tokens: tokens,
      boundUserId: bound,
    );
    final ids = RandomIdGenerator();
    final outbox = OutboxStore(db, ids: ids);
    final syncState = SyncStateStore(db);
    final engine = SyncEngine(
      transport: transport,
      outbox: outbox,
      state: syncState,
      pull: PullApplier(db),
      userId: () async => sessions.userId,
      ids: ids,
      enabled: true,
      sleep: (d) async {},
    );
    return Device._(
      stack: stack,
      path: file,
      db: db,
      repo: SqliteTaskRepository(db, ownerId: 'local-${RandomIdGenerator().nextId()}', ids: ids),
      outbox: outbox,
      state: syncState,
      sessions: sessions,
      store: secure,
      engine: engine,
      transport: transport,
    );
  }

  void close() => db.close();
}

/// Drops the response of one call after the server committed it.
final class DropResponseAfterCommit implements SyncTransport {
  DropResponseAfterCommit(this.inner, {this.drops = 1});

  final SyncTransport inner;
  int drops;
  int dropped = 0;

  @override
  Future<Map<String, Object?>> registerDevice(String deviceId, {String? label}) =>
      inner.registerDevice(deviceId, label: label);

  @override
  Future<List<Object?>> push(String deviceId, List<Map<String, Object?>> operations) async {
    final result = await inner.push(deviceId, operations);
    if (drops > 0) {
      drops--;
      dropped++;
      throw const SyncNetworkFailure('connection reset');
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> pull(String deviceId, int cursor, {int limit = 200}) =>
      inner.pull(deviceId, cursor, limit: limit);

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) => inner.resolveConflict(
    deviceId: deviceId,
    operationId: operationId,
    conflictId: conflictId,
    resolution: resolution,
    values: values,
  );

  @override
  Future<Map<String, Object?>> revokeDevice(String deviceId, String targetDeviceId) =>
      inner.revokeDevice(deviceId, targetDeviceId);
}
