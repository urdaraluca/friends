import 'package:dio/dio.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/clients/auth_client.dart';
import 'package:friends/core/api/generated/models/refresh_request.dart';
import 'package:friends/core/api/generated/models/token_pair.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'token_refresher.g.dart';

/// Owns the session's tokens: saves new pairs, clears them, and refreshes the
/// access token (contract section 4.5).
///
/// [refresh] is **single-flight**: concurrent callers share one in-flight
/// `POST /auth/refresh`. The stored refresh token is re-read right before
/// each refresh (another tab may have rotated it), and the request goes
/// through the bare Dio, so it never passes the auth interceptor.
///
/// On web every tab shares the stored refresh token (local storage) but has
/// its own access token. So when a session ends by itself (a 401), the
/// stored token is only deleted if it is still the one this instance last
/// read or saved: another tab may have stored a newer session meanwhile (a
/// password change, or a new sign-in), which must survive.
class TokenRefresher {
  new({
    required this._authClient,
    required this._store,
    required this._holder,
    required this._onSessionExpired,
  });

  final AuthClient _authClient;
  final TokenStore _store;
  final TokenHolder _holder;
  final void Function() _onSessionExpired;

  Future<void>? _inFlight;

  /// Bumped by [save] and [clear]. A refresh that started in an older
  /// generation (the user logged out or in meanwhile) doesn't touch tokens.
  int _generation = 0;

  /// The refresh token this instance last read from or wrote to the store.
  String? _refreshToken;

  /// Gets a new access token.
  ///
  /// - 401 (`refresh_invalid`, `refresh_reuse_detected`) or no stored refresh
  ///   token: clears the tokens (`clear(onlyIfOwn: true)`), calls
  ///   `onSessionExpired` and throws the [ProblemException].
  /// - 429, 5xx or a network error: throws the [ApiException] and keeps the
  ///   session, so the next call can try again.
  Future<void> refresh() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<void> _refresh() async {
    final generation = _generation;
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) {
      if (generation == _generation) await _endSession();
      throw const ProblemException(
        status: 401,
        code: ErrorCodes.refreshInvalid,
        detail: 'No stored session.',
      );
    }
    if (generation == _generation) _refreshToken = refreshToken;
    final TokenPair tokens;
    try {
      tokens = await _authClient.refreshTokens(
        body: RefreshRequest(refreshToken: refreshToken),
      );
    } on DioException catch (e, stackTrace) {
      final error = ApiException.fromDioException(e);
      if (error is ProblemException &&
          error.status == 401 &&
          generation == _generation) {
        await _endSession();
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    if (generation == _generation) await save(tokens);
  }

  /// Stores a new token pair: after login, register, refresh or a password
  /// change (which returns the only pair that is still valid).
  Future<void> save(TokenPair tokens) async {
    _generation++;
    _refreshToken = tokens.refreshToken;
    _holder.set(
      tokens.accessToken,
      expiresIn: Duration(seconds: tokens.accessExpiresIn),
    );
    await _store.writeRefreshToken(tokens.refreshToken);
  }

  /// Forgets both tokens.
  ///
  /// An explicit logout, logout-all or account deletion clears the store
  /// unconditionally. A session that ended by itself (a 401) passes
  /// [onlyIfOwn]: the stored refresh token is then kept when it isn't the one
  /// this instance last read or saved, because it is another tab's newer
  /// session.
  Future<void> clear({bool onlyIfOwn = false}) async {
    _generation++;
    final own = _refreshToken;
    _refreshToken = null;
    _holder.clear();
    if (onlyIfOwn) {
      final stored = await _store.readRefreshToken();
      if (stored != null && stored != own) return;
    }
    await _store.clear();
  }

  Future<void> _endSession() async {
    await clear(onlyIfOwn: true);
    _onSessionExpired();
  }
}

/// The app-wide [TokenRefresher], on the bare Dio.
@Riverpod(keepAlive: true)
TokenRefresher tokenRefresher(Ref ref) => TokenRefresher(
  authClient: ref.watch(publicAuthClientProvider),
  store: ref.watch(tokenStoreProvider),
  holder: ref.watch(tokenHolderProvider),
  // A callback, not a dependency: AuthController itself uses the refresher.
  onSessionExpired: () =>
      ref.read(authControllerProvider.notifier).sessionExpired(),
);
