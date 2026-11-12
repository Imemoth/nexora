import 'dart:convert';
import 'dart:io';

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

Future<({int exitCode, String stdout, String stderr})> runProcess(
  String executable,
  List<String> arguments,
  String stdin,
) async {
  final process = await Process.start(executable, arguments);
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(stdin);
  await process.stdin.close();
  final code = await process.exitCode;
  return (exitCode: code, stdout: await out, stderr: await err);
}

/// Windows Data Protection API (DPAPI, current-user scope), reached through the
/// PowerShell that ships with Windows, so no native package or approval-gated
/// dependency is needed. A value is encrypted with a key derived from the
/// signed-in Windows account: another Windows user, or a copy of the file on
/// another machine, cannot read it. Each value is its own file, written to a
/// temporary file first and then renamed, so a crash never leaves half a value.
///
/// The secret travels to PowerShell on standard input (never on the command
/// line, which other processes can read) as Base64.
final class DpapiSecureStore implements SecureStore {
  DpapiSecureStore(this.directory, {ProcessRunner? runner})
    : _run = runner ?? runProcess;

  final Directory directory;
  final ProcessRunner _run;

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

  File _file(String key) {
    if (!RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(key)) {
      throw ArgumentError.value(key, 'key', 'not a safe key');
    }
    return File('${directory.path}${Platform.pathSeparator}$key.dpapi');
  }

  Future<String> _call(String script, String inputBase64) async {
    final result = await _run('powershell.exe', [
      ..._prefix,
      script,
    ], inputBase64);
    if (result.exitCode != 0) {
      throw const AuthStorageFailure('dpapi_failed');
    }
    return result.stdout.trim();
  }

  @override
  Future<String?> read(String key) async {
    final file = _file(key);
    if (!file.existsSync()) {
      return null;
    }
    final blob = file.readAsStringSync().trim();
    if (blob.isEmpty) {
      return null;
    }
    final plain = await _call(_unprotectScript, blob);
    try {
      return utf8.decode(base64.decode(plain));
    } on FormatException {
      throw const AuthStorageFailure('dpapi_output');
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final file = _file(key);
    final blob = await _call(_protectScript, base64.encode(utf8.encode(value)));
    if (blob.isEmpty) {
      throw const AuthStorageFailure('dpapi_empty');
    }
    directory.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(blob, flush: true);
    temp.renameSync(file.path);
  }

  @override
  Future<void> delete(String key) async {
    final file = _file(key);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
}
