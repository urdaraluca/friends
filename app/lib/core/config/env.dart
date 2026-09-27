import 'package:flutter/foundation.dart';

import 'package:friends/core/config/document_base.dart';

/// Build-time configuration, passed with `--dart-define-from-file=env/<name>.json`.
abstract final class Env {
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isProd => appEnv == 'prod';

  /// Base URL of the API, without the `/api/v1` prefix or a trailing slash.
  ///
  /// The web build is served by the backend itself, so an empty value means
  /// "where the web app is": the page's `<base href>`, which the backend sets
  /// to the subpath when it is served under one (e.g. `/friends/`).
  /// Mobile builds must always set `API_BASE_URL`.
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    if (kIsWeb) return webBaseUrl(documentBaseUri());
    throw StateError(
      'API_BASE_URL is not set. Run with --dart-define-from-file=env/<env>.json',
    );
  }

  /// Whether the refresh token travels in an `HttpOnly` cookie (contract
  /// section 4.11): the web build served by the backend itself, whose API is
  /// same-origin. Mobile builds and a `flutter run` against another port keep
  /// it in the request body.
  static bool get useRefreshCookie => kIsWeb && _apiBaseUrl.isEmpty;

  /// Path of `API_BASE_URL` without a trailing slash (e.g. `/friends`), for
  /// mobile builds whose backend is served under a subpath: App Links then
  /// arrive as `/friends/join/<code>`. Empty on web, where the browser strips
  /// the `<base href>` itself, and without `API_BASE_URL`.
  static String get appLinkBasePath => kIsWeb || _apiBaseUrl.isEmpty
      ? ''
      : Uri.parse(_apiBaseUrl).path.replaceFirst(RegExp(r'/+$'), '');

  /// The directory of [base], without a trailing slash.
  @visibleForTesting
  static String webBaseUrl(Uri base) {
    final url = base.resolve('.').toString();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}
