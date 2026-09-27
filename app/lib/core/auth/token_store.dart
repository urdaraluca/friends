import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:friends/core/config/env.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// On web it only obfuscates the value in local storage, so the web build
/// served by the backend uses [CookieSessionStore] instead (contract section
/// 4.11).
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

/// [TokenStore] for cookie mode (contract section 4.11): the refresh token
/// lives in an `HttpOnly` cookie the page can't read, so this only remembers
/// **that** there is a session ([marker]), for the next page load.
///
/// A token stored by an older version (in the legacy store) is returned
/// once: the next refresh sends it in the body with the cookie header, the
/// server answers with the cookie, and [writeRefreshToken] then deletes it.
/// Nobody is signed out by the switch.
class CookieSessionStore implements TokenStore {
  new({this._prefs, TokenStore? legacy})
    : _legacy = legacy ?? SecureTokenStore();

  /// What [readRefreshToken] returns while a cookie session exists. Never
  /// sent to the server: `refresh_token` is then null.
  static const marker = 'cookie-session';

  static const _key = 'friends.cookie_session';

  SharedPreferencesAsync? _prefs;
  final TokenStore _legacy;

  SharedPreferencesAsync get _store => _prefs ??= SharedPreferencesAsync();

  @override
  Future<String?> readRefreshToken() async {
    try {
      if (await _store.getBool(_key) ?? false) return marker;
    } on Object {
      // Unreadable storage: fall through to the legacy token, if any.
    }
    return await _legacy.readRefreshToken();
  }

  @override
  Future<void> writeRefreshToken(String refreshToken) async {
    try {
      await _store.setBool(_key, true);
    } on Object {
      // Best effort: without the marker the next page load signs in again.
    }
    await _legacy.clear();
  }

  @override
  Future<void> clear() async {
    try {
      await _store.remove(_key);
    } on Object {
      // Best effort.
    }
    await _legacy.clear();
  }
}

/// Whether the refresh token travels in a cookie (`Env.useRefreshCookie`).
/// Tests override it.
@Riverpod(keepAlive: true)
bool refreshCookieMode(Ref ref) => Env.useRefreshCookie;

/// The app-wide [TokenStore]. Tests override it with an in-memory store.
@Riverpod(keepAlive: true)
TokenStore tokenStore(Ref ref) => ref.watch(refreshCookieModeProvider)
    ? CookieSessionStore()
    : SecureTokenStore();
