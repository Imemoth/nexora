import 'package:nexora/features/auth/auth_session.dart';

/// Connection settings for the synchronization runtime. Supplied at build time
/// (`--dart-define`) or by environment variables; never stored in the repository.
/// Only the project's public (anon) key is accepted: a key whose role is
/// `service_role` is refused, so the desktop application can never carry the
/// service-role key.
final class RuntimeConfig {
  const RuntimeConfig._(this.supabaseUrl, this.anonKey);

  final String supabaseUrl;
  final String anonKey;

  static const String _urlDefine = String.fromEnvironment('NEXORA_SUPABASE_URL');
  static const String _keyDefine = String.fromEnvironment(
    'NEXORA_SUPABASE_ANON_KEY',
  );

  /// Reads the build-time values, then [environment] for anything missing.
  /// Returns null when the settings are absent or unacceptable.
  static RuntimeConfig? load(Map<String, String> environment) => validate(
    _urlDefine.isNotEmpty ? _urlDefine : environment['NEXORA_SUPABASE_URL'],
    _keyDefine.isNotEmpty
        ? _keyDefine
        : environment['NEXORA_SUPABASE_ANON_KEY'],
  );

  /// Pure validation (used by tests).
  static RuntimeConfig? validate(String? url, String? key) {
    if (url == null || key == null || url.isEmpty || key.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      return null;
    }
    final local =
        uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1';
    // Tokens and passwords never travel over plain HTTP except to this machine.
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      return null;
    }
    final claims = JwtClaims.parse(key);
    if (claims != null && claims.role == 'service_role') {
      return null;
    }
    final base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return RuntimeConfig._(base, key);
  }
}
