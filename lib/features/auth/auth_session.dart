import 'dart:convert';

/// What the application knows about one signed-in session. The tokens are
/// secrets: they are only ever stored through a `SecureStore` and never logged.
final class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
    required this.isAnonymous,
  });

  final String accessToken;
  final String refreshToken;

  /// When the access token stops being accepted (UTC).
  final DateTime expiresAt;
  final String userId;
  final String? email;

  /// An anonymous identity can never synchronize and is rejected at sign-in.
  final bool isAnonymous;

  /// True while the access token is still usable for at least [margin].
  bool isFresh(DateTime now, Duration margin) =>
      expiresAt.isAfter(now.add(margin));

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
    'user_id': userId,
    'email': email,
    'is_anonymous': isAnonymous,
  };

  /// Reads a stored session. Returns null for anything malformed (a damaged
  /// record is treated as "no session", never as a crash).
  static AuthSession? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expires = json['expires_at'];
    final user = json['user_id'];
    if (access is! String ||
        refresh is! String ||
        expires is! int ||
        user is! String ||
        access.isEmpty ||
        refresh.isEmpty ||
        user.isEmpty) {
      return null;
    }
    final email = json['email'];
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expires * 1000,
        isUtc: true,
      ),
      userId: user.toLowerCase(),
      email: email is String ? email : null,
      isAnonymous: json['is_anonymous'] == true,
    );
  }
}

/// The few claims of an access token the client looks at. The signature is not
/// verified here: the server verifies it on every call. The client reads the
/// claims only to decide when to refresh and which account a token belongs to.
final class JwtClaims {
  const JwtClaims({
    required this.subject,
    required this.expiresAt,
    required this.isAnonymous,
    required this.role,
  });

  final String subject;
  final DateTime? expiresAt;
  final bool isAnonymous;
  final String? role;

  /// Returns null when [token] is not a three-part JWT with a JSON payload.
  static JwtClaims? parse(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return null;
    }
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final json = jsonDecode(payload);
      if (json is! Map) {
        return null;
      }
      final sub = json['sub'];
      if (sub is! String || sub.isEmpty) {
        return null;
      }
      final exp = json['exp'];
      return JwtClaims(
        subject: sub.toLowerCase(),
        expiresAt: exp is int
            ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
            : null,
        isAnonymous: json['is_anonymous'] == true,
        role: json['role'] is String ? json['role'] as String : null,
      );
    } on FormatException {
      return null;
    }
  }
}
