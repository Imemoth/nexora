/// Why an authentication call did not produce a session. Each case has a clear
/// consequence for local data: none of them deletes or re-assigns it.
sealed class AuthFailure implements Exception {
  const AuthFailure(this.message);

  /// Diagnostic text; never contains tokens, passwords or user data.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The request may not have reached the service (offline, timeout, 5xx). The
/// stored session is kept; the app keeps working locally.
final class AuthNetworkFailure extends AuthFailure {
  const AuthNetworkFailure(super.message);
}

/// Wrong email or password.
final class AuthInvalidCredentials extends AuthFailure {
  const AuthInvalidCredentials() : super('invalid_credentials');
}

/// The account exists but the email address is not confirmed yet.
final class AuthUnconfirmed extends AuthFailure {
  const AuthUnconfirmed() : super('email_not_confirmed');
}

/// The service is throttling this client; try again later.
final class AuthRateLimited extends AuthFailure {
  const AuthRateLimited() : super('rate_limited');
}

/// The service refused to refresh: the refresh token was revoked, reused,
/// expired or its user no longer exists. A new sign-in is required. Local data
/// stays where it is.
final class AuthSessionRevoked extends AuthFailure {
  const AuthSessionRevoked(super.message);
}

/// An anonymous identity tried to sign in. It is never accepted.
final class AuthAnonymousRejected extends AuthFailure {
  const AuthAnonymousRejected() : super('anonymous_not_allowed');
}

/// The service answered in a way the client does not understand.
final class AuthServerFailure extends AuthFailure {
  const AuthServerFailure(super.message);
}

/// The protected store could not be read or written.
final class AuthStorageFailure extends AuthFailure {
  const AuthStorageFailure(super.message);
}
