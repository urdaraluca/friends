/// Route paths and location builders. Navigate with these, never with string
/// literals: `context.go(Routes.loginWith(from: Routes.profile))`.
abstract final class Routes {
  /// Signed-in home. A placeholder until M5 (groups).
  static const home = '/';

  /// Shown while the session is restored, with Retry when that fails.
  static const splash = '/splash';

  static const login = '/login';
  static const register = '/register';
  static const profile = '/profile';

  /// API health check, for debugging. Reachable in every auth state.
  static const health = '/health';

  /// Route pattern of the public invite landing page.
  static const joinPattern = '/join/:code';

  /// Query parameter holding the location to return to after sign-in.
  static const fromParam = 'from';

  /// Query parameter pre-filling the register form's invite code.
  static const inviteParam = 'invite';

  /// `/join/<code>`.
  static String join(String code) => '/join/${Uri.encodeComponent(code)}';

  /// `/splash`, returning to [from] afterwards.
  ///
  /// Unlike the other builders, it keeps a `/login` or `/register` location
  /// with its whole query ([safeSplashFrom]). Every cold start (a page load
  /// or reload on web, a deep link) waits on the splash screen, and the
  /// register form must come back with its invite code, the login form with
  /// its `from`.
  static String splashWith({String? from}) {
    final back = safeSplashFrom(from);
    return _withQuery(splash, {fromParam: back == home ? null : back});
  }

  /// `/login`, returning to [from] after signing in.
  static String loginWith({String? from}) =>
      _withQuery(login, {fromParam: _from(from)});

  /// `/register`, returning to [from] and pre-filling [invite].
  static String registerWith({String? from, String? invite}) =>
      _withQuery(register, {fromParam: _from(from), inviteParam: invite});

  /// Paths reachable while signed out.
  static bool isPublic(String path) =>
      path == login ||
      path == register ||
      path == health ||
      path.startsWith('/join/');

  /// Paths only meant for signed-out users (and the splash screen).
  static bool isAuthOnly(String path) =>
      path == splash || path == login || path == register;

  /// [from] if it is a safe in-app location to return to, else null.
  ///
  /// Rejects absolute and protocol-relative URLs (no open redirects) and the
  /// auth screens themselves (no loops).
  static String? safeFrom(String? from) {
    final uri = _inApp(from);
    return uri == null || isAuthOnly(uri.path) ? null : from;
  }

  /// [from] if the splash screen may return to it, else null.
  ///
  /// Like [safeFrom], but `/login` and `/register` (with their query) are
  /// allowed; only `/splash` itself is rejected.
  static String? safeSplashFrom(String? from) {
    final uri = _inApp(from);
    return uri == null || uri.path == splash ? null : from;
  }

  /// Where a signed-in user who was headed to [from] lands.
  ///
  /// [from] itself when it is a safe page. An auth screen is never the
  /// destination: for `/login?from=%2Fprofile` it is that screen's own
  /// `from` (`/profile`). Otherwise [home].
  static String afterSignIn(String? from) {
    var target = from;
    // Nested `from`s are unwrapped a few levels deep at most.
    for (var depth = 0; depth < 3; depth++) {
      final uri = _inApp(target);
      if (uri == null) return home;
      if (!isAuthOnly(uri.path)) return target!;
      target = uri.queryParameters[fromParam];
    }
    return home;
  }

  /// [location] parsed, if it is a relative in-app location. Rejects absolute
  /// and protocol-relative URLs (no open redirects).
  static Uri? _inApp(String? location) {
    if (location == null ||
        !location.startsWith('/') ||
        location.startsWith('//')) {
      return null;
    }
    final uri = Uri.tryParse(location);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    return uri;
  }

  static String? _from(String? from) {
    final safe = safeFrom(from);
    return safe == home ? null : safe;
  }

  static String _withQuery(String path, Map<String, String?> query) {
    final params = {
      for (final MapEntry(:key, :value) in query.entries)
        if (value != null && value.isNotEmpty) key: value,
    };
    return params.isEmpty
        ? path
        : Uri(path: path, queryParameters: params).toString();
  }
}
