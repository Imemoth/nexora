import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/features/auth/account_paths.dart';
import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/native_dpapi.dart';
import 'package:nexora/features/auth/secure_store.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nexora-store-'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('DpapiSecureStore file handling (fake protector)', () {
    // A reversible stand-in for DPAPI: base64 of base64, plus a marker.
    Future<({int exitCode, String stdout, String stderr})> fake(
      String exe,
      List<String> args,
      String stdin,
    ) async {
      final isProtect = args.last.contains('::Protect(');
      final input = stdin.trim();
      final out = isProtect
          ? base64.encode(utf8.encode('P:$input'))
          : utf8.decode(base64.decode(input)).substring(2);
      return (exitCode: 0, stdout: out, stderr: '');
    }

    test('round trip, overwrite, delete, and no plain text on disk', () async {
      final store = DpapiSecureStore(dir, runner: fake);
      await store.write('session', 'refresh-token-secret');
      expect(await store.read('session'), 'refresh-token-secret');
      await store.write('session', 'second');
      expect(await store.read('session'), 'second');

      final raw = File('${dir.path}${Platform.pathSeparator}session.dpapi')
          .readAsStringSync();
      expect(raw.contains('second'), isFalse);
      expect(
        Directory(dir.path)
            .listSync()
            .whereType<File>()
            .map((f) => f.path.split(Platform.pathSeparator).last),
        ['session.dpapi'],
      );

      await store.delete('session');
      expect(await store.read('session'), isNull);
    });

    test(
      'the secret goes to the program on stdin, never on the command line',
      () async {
        final seen = <List<String>>[];
        final stdins = <String>[];
        final store = DpapiSecureStore(
          dir,
          runner: (exe, args, stdin) {
            seen.add(args);
            stdins.add(stdin);
            return fake(exe, args, stdin);
          },
        );
        await store.write('session', 'sekret');
        expect(seen.expand((a) => a).any((a) => a.contains('sekret')), isFalse);
        expect(stdins.single.contains('sekret'), isFalse); // Base64, not raw
        expect(base64.decode(stdins.single.trim()), utf8.encode('sekret'));
      },
    );

    test('a failing protector is reported and nothing is written', () async {
      final store = DpapiSecureStore(
        dir,
        runner: (a, b, c) async => (exitCode: 1, stdout: '', stderr: 'boom'),
      );
      await expectLater(
        store.write('session', 'x'),
        throwsA(isA<AuthStorageFailure>()),
      );
      expect(
        File('${dir.path}${Platform.pathSeparator}session.dpapi').existsSync(),
        isFalse,
      );
    });

    test('unsafe keys are refused', () async {
      final store = DpapiSecureStore(dir, runner: fake);
      await expectLater(store.write('../x', 'v'), throwsArgumentError);
      await expectLater(store.read('a/b'), throwsArgumentError);
    });
  });

  test(
    'real DPAPI: round trip, and the file holds no plain text',
    () async {
      final store = DpapiSecureStore(dir);
      const secret = 'refresh-token-ünïcode-0123456789';
      await store.write('session', secret);
      expect(await store.read('session'), secret);
      final raw = File('${dir.path}${Platform.pathSeparator}session.dpapi')
          .readAsStringSync();
      expect(raw.contains('refresh'), isFalse);
      // a damaged blob is an error, not garbage
      File('${dir.path}${Platform.pathSeparator}session.dpapi')
          .writeAsStringSync('AAAA');
      await expectLater(
        store.read('session'),
        throwsA(isA<AuthStorageFailure>()),
      );
    },
    skip: Platform.isWindows
        ? null
        : 'DPAPI exists only on Windows; the Windows CI job runs this test',
  );

  group('account paths', () {
    final paths = AccountPaths(Directory('root'));
    test('a user id becomes one folder under accounts', () {
      final f = paths.databaseFor('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA');
      expect(f.path.contains('accounts'), isTrue);
      expect(f.path.contains('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), isTrue);
      expect(f.path.endsWith('nexora.db'), isTrue);
    });

    test('anything that is not a UUID is refused (no path escape)', () {
      for (final bad in ['..', '../x', 'a/b', '', 'not-a-uuid', r'..\\x']) {
        expect(() => paths.databaseFor(bad), throwsArgumentError, reason: bad);
      }
    });

    test('two accounts never share a file', () {
      expect(
        paths.databaseFor('11111111-1111-4111-8111-111111111111').path,
        isNot(paths.databaseFor('22222222-2222-4222-8222-222222222222').path),
      );
    });
  });

  group('bounded and contained failures', () {
    test('a protector that never answers ends in dpapi_timeout', () async {
      final store = DpapiSecureStore(
        dir,
        protector: _HangingProtector(),
        timeout: const Duration(milliseconds: 150),
      );
      await expectLater(
        store.write('session', 'x'),
        throwsA(
          isA<AuthStorageFailure>().having(
            (e) => e.message,
            'message',
            'dpapi_timeout',
          ),
        ),
      );
      expect(
        File('${dir.path}${Platform.pathSeparator}session.dpapi').existsSync(),
        isFalse,
      );
    });

    test('an unexpected protector exception is an AuthStorageFailure', () async {
      final store = DpapiSecureStore(dir, protector: _ThrowingProtector());
      await expectLater(
        store.write('session', 'x'),
        throwsA(isA<AuthStorageFailure>()),
      );
    });

    test('a program that cannot be started is an AuthStorageFailure', () async {
      await expectLater(
        runProcess('nexora-no-such-program-0123', const [], ''),
        throwsA(isA<AuthStorageFailure>()),
      );
    });

    test(
      'a stuck helper process is killed after the timeout (Windows)',
      () async {
        final watch = Stopwatch()..start();
        await expectLater(
          runProcess('powershell.exe', const [
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            'Start-Sleep -Seconds 60',
          ], '', timeout: const Duration(seconds: 3)),
          throwsA(isA<AuthStorageFailure>()),
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 30)));
      },
      skip: !Platform.isWindows,
    );
  });

  group('real Windows DPAPI, native implementation', () {
    test('round trip, restart, cross-compatibility with PowerShell', () async {
      const secret = 'refresh-token-ünïcode-0123456789';
      final native = DpapiSecureStore(dir, protector: NativeDpapiProtector());
      await native.write('session', secret);
      final raw = File('${dir.path}${Platform.pathSeparator}session.dpapi')
          .readAsStringSync();
      expect(raw.contains('refresh'), isFalse);
      // a new instance (an application restart) reads it
      expect(
        await DpapiSecureStore(
          dir,
          protector: NativeDpapiProtector(),
        ).read('session'),
        secret,
      );
      // PowerShell reads what native wrote, and the other way round
      expect(await DpapiSecureStore(dir).read('session'), secret);
      await DpapiSecureStore(dir).write('other', 'from-powershell');
      expect(
        await DpapiSecureStore(
          dir,
          protector: NativeDpapiProtector(),
        ).read('other'),
        'from-powershell',
      );
    }, skip: !Platform.isWindows);

    test('a damaged blob is an error, never garbage', () async {
      final native = DpapiSecureStore(dir, protector: NativeDpapiProtector());
      await native.write('session', 'x');
      File('${dir.path}${Platform.pathSeparator}session.dpapi')
          .writeAsStringSync('AAAA');
      await expectLater(
        native.read('session'),
        throwsA(isA<AuthStorageFailure>()),
      );
    }, skip: !Platform.isWindows);

    test('the native protector is unavailable (and says so) off Windows', () {
      expect(
        NativeDpapiProtector.new,
        throwsA(isA<AuthStorageFailure>()),
      );
    }, skip: Platform.isWindows);
  });
}

final class _HangingProtector implements DataProtector {
  @override
  Future<Uint8List> protect(Uint8List plain) => Completer<Uint8List>().future;

  @override
  Future<Uint8List> unprotect(Uint8List blob) =>
      Completer<Uint8List>().future;
}

final class _ThrowingProtector implements DataProtector {
  @override
  Future<Uint8List> protect(Uint8List plain) async => throw StateError('x');

  @override
  Future<Uint8List> unprotect(Uint8List blob) async => throw StateError('x');
}
