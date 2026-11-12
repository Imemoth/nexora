import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nexora/features/sync/sync_transport.dart';

/// Integration harness: a disposable PostgreSQL database built from the real
/// migrations (S1 to S4) and a [SyncTransport] that calls the real RPCs through
/// `psql` as the `authenticated` role with JWT claims, exactly like the
/// supabase-tests suites do. It never connects to a hosted project: it needs the
/// standard PG* environment variables of a local or CI server and the opt-in
/// flag `NEXORA_E2E_PG=1`.
///
/// Limitation, stated plainly: PostgREST and real JWT verification are **not**
/// exercised (claims are set in the transaction like PostgREST would). The hosted
/// HTTP acceptance gate stays open.
final bool e2eEnabled = Platform.environment['NEXORA_E2E_PG'] == '1';

final class PsqlResult {
  const PsqlResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

Future<PsqlResult> runPsql(String database, String script) async {
  final process = await Process.start('psql', ['-X', '-q', '-tA', '-v', 'ON_ERROR_STOP=1', '-d', database]);
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(script);
  await process.stdin.close();
  final code = await process.exitCode;
  return PsqlResult(code, await out, await err);
}

Future<String> mustPsql(String database, String script) async {
  final result = await runPsql(database, script);
  if (result.exitCode != 0) {
    throw StateError('psql failed: ${result.stderr}');
  }
  return result.stdout.trim();
}

/// A fresh database with every migration applied. Returns its name.
Future<String> createE2eDatabase() async {
  final name = 'nx_e2e_${Random().nextInt(1 << 30)}';
  await mustPsql('postgres', 'drop database if exists $name;\ncreate database $name;');
  final roles = await mustPsql('postgres', "select 1 from pg_roles where rolname = 'anon';");
  var bootstrap = File('supabase/tests/00_bootstrap_local.sql').readAsStringSync();
  if (roles == '1') {
    bootstrap = bootstrap.split('\n').where((l) => !l.startsWith('create role')).join('\n');
  }
  await mustPsql(name, bootstrap);
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    await mustPsql(name, file.readAsStringSync());
  }
  return name;
}

Future<void> dropE2eDatabase(String name) async {
  await runPsql('postgres', 'drop database if exists $name;');
}

String _lit(String text) => '\$nx\$$text\$nx\$';

/// Calls the real S2/S3/S4 RPCs as `authenticated` for [userId].
final class PsqlTransport implements SyncTransport {
  PsqlTransport({required this.database, required this.userId});

  final String database;
  final String userId;

  Future<Object?> _call(String expression) async {
    final claims = jsonEncode({'sub': userId, 'role': 'authenticated', 'aud': 'authenticated', 'is_anonymous': false});
    final script = '\\set VERBOSITY verbose\n'
        'begin;\n'
        'do \$\$ begin perform set_config(\'request.jwt.claims\', ${_lit(claims)}, true); end \$\$;\n'
        'set local role authenticated;\n'
        'select $expression;\n'
        'commit;\n';
    final PsqlResult result;
    try {
      result = await runPsql(database, script);
    } on ProcessException {
      throw const SyncNetworkFailure('psql_unavailable');
    }
    if (result.exitCode != 0) {
      throw _classify(result.stderr);
    }
    final line = result.stdout.split('\n').where((l) => l.trim().isNotEmpty).lastOrNull;
    return line == null ? null : jsonDecode(line);
  }

  SyncTransportException _classify(String stderr) {
    final match = RegExp(r'ERROR:\s+(\w{5}):\s+(.*)').firstMatch(stderr);
    if (match == null) {
      return SyncNetworkFailure('psql: ${stderr.split('\n').first}');
    }
    final state = match.group(1)!;
    final message = match.group(2)!.trim();
    if (state == '28000') {
      return const SyncAuthFailure('unauthenticated');
    }
    if (state == '42501' && message == 'anonymous_not_allowed') {
      return const SyncAuthFailure('anonymous_not_allowed', anonymous: true);
    }
    if (state.startsWith('40') || state.startsWith('53') || state.startsWith('55') || state.startsWith('57')) {
      return SyncNetworkFailure('transient_$state');
    }
    return SyncServerError(message);
  }

  Map<String, Object?> _object(Object? value) => Map<String, Object?>.from(value! as Map);

  @override
  Future<Map<String, Object?>> registerDevice(String deviceId, {String? label}) async =>
      _object(await _call("public.nexora_register_device('$deviceId'::uuid, ${label == null ? 'null' : _lit(label)})"));

  @override
  Future<List<Object?>> push(String deviceId, List<Map<String, Object?>> operations) async {
    final body = _object(await _call("public.nexora_sync_push('$deviceId'::uuid, ${_lit(jsonEncode(operations))}::jsonb)"));
    return body['results']! as List<Object?>;
  }

  @override
  Future<Map<String, Object?>> pull(String deviceId, int cursor, {int limit = 200}) async =>
      _object(await _call("public.nexora_sync_pull('$deviceId'::uuid, $cursor, $limit)"));

  @override
  Future<Map<String, Object?>> resolveConflict({
    required String deviceId,
    required String operationId,
    required String conflictId,
    required String resolution,
    Map<String, Object?>? values,
  }) async =>
      _object(await _call(
        "public.nexora_resolve_conflict('$deviceId'::uuid, '$operationId'::uuid, '$conflictId'::uuid, '$resolution', "
        '${values == null ? 'null' : '${_lit(jsonEncode(values))}::jsonb'})',
      ));

  @override
  Future<Map<String, Object?>> revokeDevice(String deviceId, String targetDeviceId) async =>
      _object(await _call("public.nexora_revoke_device('$deviceId'::uuid, '$targetDeviceId'::uuid)"));
}
