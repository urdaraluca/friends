import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'token_holder.g.dart';

/// The access token and its expiry, kept **in memory only** (contract
/// section 12). The refresh token lives in the `TokenStore`.
class TokenHolder {
  /// [clock] defaults to `DateTime.now`; tests pass a fake one.
  new({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  String? _accessToken;
  DateTime? _expiresAt;

  /// The current access token, or null when signed out or not yet restored.
  String? get accessToken => _accessToken;

  /// When [accessToken] expires (device clock).
  DateTime? get expiresAt => _expiresAt;

  /// Stores a new access token that is valid for [expiresIn] from now.
  void set(String accessToken, {required Duration expiresIn}) {
    _accessToken = accessToken;
    _expiresAt = _clock().add(expiresIn);
  }

  /// Forgets the access token.
  void clear() {
    _accessToken = null;
    _expiresAt = null;
  }

  /// Whether there is a token that expires within [window] (or already has).
  bool expiresWithin(Duration window) {
    final expiresAt = _expiresAt;
    if (_accessToken == null || expiresAt == null) return false;
    return !expiresAt.isAfter(_clock().add(window));
  }

  /// Whether there is a token that hasn't expired yet.
  bool get isValid {
    final expiresAt = _expiresAt;
    return _accessToken != null &&
        expiresAt != null &&
        expiresAt.isAfter(_clock());
  }
}

/// The app-wide [TokenHolder].
@Riverpod(keepAlive: true)
TokenHolder tokenHolder(Ref ref) => TokenHolder();
