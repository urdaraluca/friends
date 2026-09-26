import 'dart:convert';

/// Reads claims of an access token (a JWT, contract section 4.1) **without
/// verifying it**. The server verifies every token; the app only needs to
/// know which account a token belongs to.
abstract final class AccessToken {
  /// The `sub` claim (the user ID) of [token], or null when [token] isn't a
  /// readable JWT.
  static String? subject(String? token) {
    if (token == null) return null;
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final sub = payload is Map ? payload['sub'] : null;
      return sub is String ? sub : null;
    } on FormatException {
      return null;
    }
  }
}
