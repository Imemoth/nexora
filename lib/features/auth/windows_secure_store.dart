import 'dart:io';

import 'auth_diagnostics.dart';
import 'native_dpapi.dart';
import 'secure_store.dart';

/// The protected session store of the Windows application.
///
/// Uses DPAPI called directly in-process ([NativeDpapiProtector]); when that
/// cannot be set up, or when the environment variable `NEXORA_DPAPI` is
/// `powershell`, it falls back to the PowerShell implementation. Both write the
/// same file format, so either can read what the other wrote.
SecureStore createWindowsSecureStore(
  Directory directory, {
  AuthLog log = const NullAuthLog(),
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  if (env['NEXORA_DPAPI'] != 'powershell') {
    try {
      final native = NativeDpapiProtector();
      log.log('store.dpapi', {'implementation': 'native'});
      return DpapiSecureStore(directory, protector: native, log: log);
    } on Object catch (error) {
      log.log('store.dpapi.native_unavailable', {'type': error.runtimeType});
    }
  }
  log.log('store.dpapi', {'implementation': 'powershell'});
  return DpapiSecureStore(directory, log: log);
}
