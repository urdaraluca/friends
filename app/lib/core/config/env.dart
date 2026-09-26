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

  /// The directory of [base], without a trailing slash.
  @visibleForTesting
  static String webBaseUrl(Uri base) {
    final url = base.resolve('.').toString();
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
}
