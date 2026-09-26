import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'token_store.g.dart';

/// Persists the refresh token between app launches.
abstract interface class TokenStore {
  /// The stored refresh token, or null when there is no session.
  Future<String?> readRefreshToken();

  /// Replaces the stored refresh token.
  Future<void> writeRefreshToken(String refreshToken);

  /// Removes the stored refresh token.
  Future<void> clear();
}

/// [TokenStore] on `flutter_secure_storage`: the Keychain on iOS, the
/// Keystore on Android.
///
/// On web it only obfuscates the value in local storage. That is accepted for
/// the MVP (contract section 12): the app is served from the API's own origin
/// and access tokens live for 15 minutes.
class SecureTokenStore implements TokenStore {
  new([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _refreshTokenKey = 'friends.refresh_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() async {
    try {
      return await _storage.read(key: _refreshTokenKey);
    } on PlatformException {
      // Unreadable (e.g. the Android keystore was reset): no session.
      return null;
    }
  }

  @override
  Future<void> writeRefreshToken(String refreshToken) =>
      _storage.write(key: _refreshTokenKey, value: refreshToken);

  @override
  Future<void> clear() => _storage.delete(key: _refreshTokenKey);
}

/// The app-wide [TokenStore]. Tests override it with an in-memory store.
@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => SecureTokenStore();
