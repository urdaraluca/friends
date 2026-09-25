import 'package:flutter/foundation.dart';

/// Build-time configuration, passed with `--dart-define-from-file=env/<name>.json`.
abstract final class Env {
  static const String appEnv = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isProd => appEnv == 'prod';

  /// Origin of the API, without the `/api/v1` prefix.
  ///
  /// The web build is served by the backend itself, so an empty value means
  /// "same origin". Mobile builds must always set `API_BASE_URL`.
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    if (kIsWeb) return Uri.base.origin;
    throw StateError(
      'API_BASE_URL is not set. Run with --dart-define-from-file=env/<env>.json',
    );
  }
}
