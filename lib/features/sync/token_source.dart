/// Where the sync layer gets the signed-in user's access token. The
/// authentication layer implements it; the sync layer never sees a password, a
/// refresh token or a storage detail.
abstract interface class TokenSource {
  /// The signed-in server account, or null when signed out.
  String? get userId;

  /// A usable access token (refreshed when needed), or null when signed out.
  /// Throws `SyncNetworkFailure` when a refresh is needed but cannot happen now.
  Future<String?> accessToken();

  /// The server rejected the token. Refreshes once; true when a new token is
  /// ready.
  Future<bool> refreshAfterRejection();
}
