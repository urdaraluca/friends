import 'dart:async';

import 'package:dio/dio.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/access_token.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_refresher.dart';

/// Requests that need no access token (contract section 12): health, login,
/// register, refresh, logout and the invite preview.
///
/// The generated clients can't set `options.extra`, so they are recognised by
/// method and path; other code may also set `extra['public'] = true`.
abstract final class PublicEndpoints {
  /// `options.extra` key that marks a request as public.
  static const extraKey = 'public';

  static final _routes = <(String, RegExp)>[
    ('POST', RegExp(r'/api/v1/auth/(login|register|refresh|logout)$')),
    ('GET', RegExp(r'/api/v1/invites/[^/]+$')),
    ('GET', RegExp(r'/api/v1/health$')),
  ];

  /// Whether [options] is a public request.
  static bool matches(RequestOptions options) {
    if (options.extra[extraKey] == true) return true;
    final method = options.method.toUpperCase();
    final path = options.uri.path;
    return _routes.any((r) => r.$1 == method && r.$2.hasMatch(path));
  }
}

/// Stamps every request with the signed-in user's ID when it is **issued**
/// (`options.extra['user_id']`), before [AuthInterceptor] queues it.
///
/// [AuthInterceptor] only sends a request with an access token of that same
/// account. On web the tabs share the stored refresh token, so a refresh can
/// return another account's session (another tab signed in as someone else);
/// a request built from this tab's screens must not reach the server as that
/// account.
class AccountStampInterceptor extends Interceptor {
  new(this._currentUserId);

  /// `options.extra` key of the stamp (null while signed out or restoring).
  static const extraKey = 'user_id';

  final String? Function() _currentUserId;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra.putIfAbsent(extraKey, _currentUserId);
    handler.next(options);
  }
}

/// Attaches the access token and keeps it fresh (contract sections 4 and 12).
///
/// - Public calls ([PublicEndpoints]) pass through untouched, marked with
///   `extra['public'] = true`. The app sends them on the bare Dio anyway
///   (`publicApiProvider`), so they never wait in this queue.
/// - `onRequest`: when the token expires within [refreshWindow], it refreshes
///   first. Requests are queued meanwhile, so they all get the new token.
/// - `onError` on `401 token_expired` (not yet retried): if the request used
///   an older token than the current one, it just retries; otherwise it
///   refreshes once and retries once (`extra['retried'] = true`).
/// - Any other problem+json 401 calls `onSessionExpired`, unless it answered
///   a token from an older session. A 401 that isn't problem+json (a proxy
///   or captive portal, not the API) passes through without signing out.
/// - Network errors never sign the user out.
/// - A request stamped by [AccountStampInterceptor] for one account is never
///   sent (or retried) with another account's token: it fails with a 401
///   `unauthenticated` [ProblemException] and `onAccountChanged` gets the
///   token's user ID.
///
/// Retries go through `retryDio` (the bare Dio): a retry through this queued
/// interceptor would wait behind the error it is handling.
class AuthInterceptor extends QueuedInterceptorsWrapper {
  new({
    required this._tokens,
    required this._refresher,
    required this._retryDio,
    required this._onSessionExpired,
    this._onAccountChanged,
    this.refreshWindow = const Duration(seconds: 30),
  });

  /// `options.extra` key set on the single retry of a request.
  static const retriedKey = 'retried';

  /// The error of a request refused because the access token belongs to
  /// another account than the one the request was issued for.
  static const accountChangedError = ProblemException(
    status: 401,
    code: ErrorCodes.unauthenticated,
    detail: 'Another account signed in on this device.',
  );

  /// Refresh proactively when the token expires within this window.
  final Duration refreshWindow;

  final TokenHolder _tokens;
  final TokenRefresher _refresher;
  final Dio _retryDio;
  final void Function() _onSessionExpired;
  final void Function(String userId)? _onAccountChanged;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (PublicEndpoints.matches(options)) {
      options.extra[PublicEndpoints.extraKey] = true;
      return handler.next(options);
    }
    if (_tokens.expiresWithin(refreshWindow)) {
      try {
        await _refresher.refresh();
      } on ApiException catch (e) {
        // Keep going while the old token still works (e.g. a 429 on
        // refresh); otherwise fail with the refresh error.
        if (!_tokens.isValid) {
          return handler.reject(
            DioException(
              requestOptions: options,
              error: e,
              type: e is NetworkException
                  ? DioExceptionType.connectionError
                  : DioExceptionType.unknown,
            ),
            true,
          );
        }
      }
    }
    final token = _tokens.accessToken;
    if (token != null) {
      if (!_sameAccount(options, token)) {
        return handler.reject(
          DioException(requestOptions: options, error: accountChangedError),
          true,
        );
      }
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 401 || PublicEndpoints.matches(options)) {
      return handler.next(err);
    }
    final usedToken = _bearerToken(options);
    final problem = ProblemException.fromResponse(err.response);
    if (problem?.code == ErrorCodes.tokenExpired &&
        options.extra[retriedKey] != true) {
      if (_tokens.accessToken == null) return handler.next(err);
      if (usedToken == _tokens.accessToken) {
        try {
          await _refresher.refresh();
        } on ApiException catch (e) {
          return handler.next(err.copyWith(error: e));
        }
      }
      await _retry(err, handler);
      return;
    }
    if (_endsSession(err.response)) _sessionEndedFor(usedToken);
    handler.next(err);
  }

  Future<void> _retry(DioException err, ErrorInterceptorHandler handler) async {
    final token = _tokens.accessToken;
    if (token == null) return handler.next(err);
    if (!_sameAccount(err.requestOptions, token)) {
      return handler.next(err.copyWith(error: accountChangedError));
    }
    final options = err.requestOptions.copyWith(
      headers: {
        ...err.requestOptions.headers,
        'Authorization': 'Bearer $token',
      },
      extra: {...err.requestOptions.extra, retriedKey: true},
    );
    try {
      handler.resolve(await _retryDio.fetch<Object?>(options));
    } on DioException catch (retryError) {
      if (_endsSession(retryError.response)) _sessionEndedFor(token);
      handler.next(retryError);
    }
  }

  /// Whether [response] is the API saying the session is over: a
  /// problem+json 401 other than `token_expired` (`unauthenticated`,
  /// `refresh_invalid`, `refresh_reuse_detected`). A 401 without a problem
  /// body (a proxy's auth wall, a captive portal) isn't the API, so it never
  /// signs out, just as on `POST /auth/refresh`.
  static bool _endsSession(Response<Object?>? response) =>
      ProblemException.fromResponse(response)?.endsSession ?? false;

  /// Whether [token] belongs to the account [options] was issued for (see
  /// [AccountStampInterceptor]). Unstamped requests (issued while signed out
  /// or restoring) and tokens that aren't readable JWTs always match. On a
  /// mismatch, `onAccountChanged` gets the token's user ID.
  bool _sameAccount(RequestOptions options, String token) {
    final issuedFor = options.extra[AccountStampInterceptor.extraKey];
    if (issuedFor is! String) return true;
    final subject = AccessToken.subject(token);
    if (subject == null || subject == issuedFor) return true;
    _onAccountChanged?.call(subject);
    return false;
  }

  /// Signs out, unless [usedToken] belongs to an older session: a late 401
  /// for a previous account must not end the current one.
  void _sessionEndedFor(String? usedToken) {
    if (usedToken == _tokens.accessToken) _onSessionExpired();
  }

  static String? _bearerToken(RequestOptions options) {
    final header = options.headers['Authorization'];
    if (header is String && header.startsWith('Bearer ')) {
      return header.substring('Bearer '.length);
    }
    return null;
  }
}
