import 'package:nexora/features/auth/auth_failure.dart';
import 'package:nexora/features/auth/session_manager.dart';
import 'package:nexora/features/sync/sync_transport.dart';
import 'package:nexora/features/sync/token_source.dart';

/// Adapts the session manager to the sync layer's [TokenSource], translating
/// authentication failures into the transport failures the engine understands.
final class SessionTokenSource implements TokenSource {
  SessionTokenSource(this._manager);

  final SessionManager _manager;

  @override
  String? get userId => _manager.userId;

  @override
  Future<String?> accessToken() async {
    try {
      return await _manager.accessToken();
    } on AuthNetworkFailure catch (error) {
      throw SyncNetworkFailure('auth_${error.message}');
    } on AuthRateLimited {
      throw const SyncNetworkFailure('auth_rate_limited');
    } on AuthFailure catch (error) {
      throw SyncAuthFailure('auth_${error.message}');
    }
  }

  @override
  Future<bool> refreshAfterRejection() => _manager.refreshAfterRejection();
}
