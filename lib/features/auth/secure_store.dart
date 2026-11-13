import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'auth_diagnostics.dart';
import 'auth_failure.dart';

/// Protected storage for session material (refresh and access tokens). The
/// application never writes tokens anywhere else: not to SQLite, not to logs,
/// not to plain files.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// For tests and for builds that must never persist a session.
final class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Runs an external program with [stdin] and returns its output. Injectable so
/// the file handling can be tested without Windows.
typedef ProcessRunner =
    Future<({int exitCode, String stdout, String stderr})> Function(
      String executable,
      List<String> arguments,
      String stdin,
    );

/// Runs [executable], feeds it [stdin], closes standard input, and waits for it
/// to exit. The wait is bounded: when the program has not finished within
/// [timeout] it is killed and an [AuthStorageFailure] (`dpapi_timeout`) is
/// thrown, so a stuck helper can never hang the caller. Problems starting the
/// program or writing to it become [AuthStorageFailure]s as well.
Future<({int exitCode, String stdout, String stderr})> runProcess(
  String executable,
  List<String> arguments,
  String stdin, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final Process process;
  try {
    process = await Process.start(executable, arguments);
  } on ProcessException {
    throw const AuthStorageFailure('dpapi_start');
  }
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  Future<void> feed() async {
    try {
      process.stdin.write(stdin);
      await process.stdin.close();
    } on Object {
      // the program may already have exited; its exit code tells the story
    }
  }

  try {
    await feed();
    final code = await process.exitCode.timeout(timeout);
    return (
      exitCode: code,
      stdout: await out.timeout(timeout),
      stderr: await err.timeout(timeout),
    );
  } on TimeoutException {
    process.kill();
    throw const AuthStorageFailure('dpapi_timeout');
  }
}

/// Encrypts and decrypts small byte strings for the current Windows user.
abstract interface class DataProtector {
  Future<Uint8List> protect(Uint8List plain);
  Future<Uint8List> unprotect(Uint8List blob);
}

/// DPAPI through the PowerShell that ships with Windows (the secret travels on
/// standard input as Base64, never on the command line).
final class PowerShellProtector implements DataProtector {
  PowerShellProtector({
    ProcessRunner? runner,
    AuthLog log = const NullAuthLog(),
  }) : _run = runner ?? runProcess,
       _log = log;

  final ProcessRunner _run;
  final AuthLog _log;

  static const List<String> _prefix = [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
  ];

  static const String _protectScript =
      r"$ErrorActionPreference='Stop';"
      r'Add-Type -AssemblyName System.Security;'
      r'$in=[Console]::In.ReadToEnd().Trim();'
      r'$p=[Convert]::FromBase64String($in);'
      r"$e=[Text.Encoding]::UTF8.GetBytes('Nexora.Auth.v1');"
      r'$o=[Security.Cryptography.ProtectedData]::Protect($p,$e,[Security.Cryptography.DataProtectionScope]::CurrentUser);'
      r'[Console]::Out.Write([Convert]::ToBase64String($o))';

  static const String _unprotectScript =
      r"$ErrorActionPreference='Stop';"
      r'Add-Type -AssemblyName System.Security;'
      r'$in=[Console]::In.ReadToEnd().Trim();'
      r'$b=[Convert]::FromBase64String($in);'
      r"$e=[Text.Encoding]::UTF8.GetBytes('Nexora.Auth.v1');"
      r'$o=[Security.Cryptography.ProtectedData]::Unprotect($b,$e,[Security.Cryptography.DataProtectionScope]::CurrentUser);'
      r'[Console]::Out.Write([Convert]::ToBase64String($o))';

  Future<Uint8List> _call(String op, String script, Uint8List input) async {
    _log.log('dpapi.powershell.start', {'op': op});
    final watch = Stopwatch()..start();
    final result = await _run('powershell.exe', [
      ..._prefix,
      script,
    ], base64.encode(input));
    _log.log('dpapi.powershell.done', {
      'op': op,
      'exit': result.exitCode,
      'ms': watch.elapsedMilliseconds,
    });
    if (result.exitCode != 0) {
      throw const AuthStorageFailure('dpapi_failed');
    }
    try {
      return base64.decode(result.stdout.trim());
    } on FormatException {
      throw const AuthStorageFailure('dpapi_output');
    }
  }

  @override
  Future<Uint8List> protect(Uint8List plain) =>
      _call('protect', _protectScript, plain);

  @override
  Future<Uint8List> unprotect(Uint8List blob) =>
      _call('unprotect', _unprotectScript, blob);
}

/// Windows Data Protection API (DPAPI, current-user scope). A value is
/// encrypted with a key derived from the signed-in Windows account: another
/// Windows user, or a copy of the file on another machine, cannot read it. Each
/// value is its own file, written to a temporary file first and then renamed, so
/// a crash never leaves half a value. Every operation is bounded by [timeout].
final class DpapiSecureStore implements SecureStore {
  DpapiSecureStore(
    this.directory, {
    ProcessRunner? runner,
    DataProtector? protector,
    this.log = const NullAuthLog(),
    this.timeout = const Duration(seconds: 45),
  }) : _protector = protector ?? PowerShellProtector(runner: runner, log: log);

  final Directory directory;
  final AuthLog log;
  final Duration timeout;
  final DataProtector _protector;

  File _file(String key) {
    if (!RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'not a safe key');
    }
    return File('${directory.path}${Platform.pathSeparator}$key.dpapi');
  }

  /// Runs [action] but never longer than [timeout]; any failure becomes an
  /// [AuthStorageFailure] (a `dpapi_timeout` when it was too slow).
  Future<T> _bounded<T>(String op, Future<T> Function() action) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      log.log('dpapi.timeout', {'op': op});
      throw const AuthStorageFailure('dpapi_timeout');
    } on AuthFailure {
      rethrow;
    } on Object catch (error) {
      log.log('dpapi.error', {'op': op, 'type': error.runtimeType});
      throw const AuthStorageFailure('dpapi_error');
    }
  }

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    if (!file.existsSync()) {
      return null;
    }
    final text = file.readAsStringSync().trim();
    if (text.isEmpty) {
      return null;
    }
    final Uint8List blob;
    try {
      blob = base64.decode(text);
    } on FormatException {
      throw const AuthStorageFailure('dpapi_output');
    }
    final plain = await _bounded('read', () => _protector.unprotect(blob));
    try {
      return utf8.decode(plain);
    } on FormatException {
      throw const AuthStorageFailure('dpapi_output');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = _file(key);
    final blob = await _bounded(
      'write',
      () => _protector.protect(Uint8List.fromList(utf8.encode(value))),
    );
    if (blob.isEmpty) {
      throw const AuthStorageFailure('dpapi_empty');
    }
    try {
      directory.createSync(recursive: true);
      final temp = File('${file.path}.tmp');
      temp.writeAsStringSync(base64.encode(blob), flush: true);
      temp.renameSync(file.path);
    } on FileSystemException {
      throw const AuthStorageFailure('store_file');
    }
    log.log('dpapi.write.done', {'key': key});
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
