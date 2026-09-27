import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:friends/core/network/dio_provider.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/test_backend.dart';

/// Cookie mode for the web build (contract section 4.11): the refresh token
/// stays in an HttpOnly cookie, and the app only keeps a session marker.
void main() {
  group('CookieSessionStore', () {
    test('keeps a marker, not the token', () async {
      final prefs = FakePrefs();
      final store = CookieSessionStore(
        prefs: prefs,
        legacy: InMemoryTokenStore(),
      );

      expect(await store.readRefreshToken(), isNull);
      await store.writeRefreshToken(CookieSessionStore.marker);
      expect(await store.readRefreshToken(), CookieSessionStore.marker);
      expect(prefs.data.values, [true]); // no token anywhere
      await store.clear();
      expect(await store.readRefreshToken(), isNull);
    });

    test('an older stored token is used once, then deleted', () async {
      final legacy = InMemoryTokenStore('refresh-legacy');
      final store = CookieSessionStore(prefs: FakePrefs(), legacy: legacy);

      expect(await store.readRefreshToken(), 'refresh-legacy');
      await store.writeRefreshToken(CookieSessionStore.marker);

      expect(legacy.refreshToken, isNull);
      expect(await store.readRefreshToken(), CookieSessionStore.marker);
    });
  });

  group('the session in cookie mode', () {
    late TestBackend backend;
    late ProviderContainer container;

    AuthController auth() => container.read(authControllerProvider.notifier);

    test('login, restore and logout never handle the refresh token', () async {
      backend = TestBackend(cookieMode: true);
      backend.adapter
        ..onJson(
          'POST',
          ApiPaths.login,
          authSessionJson(tokens: tokenPairJson(access: 'a-1', refresh: null)),
        )
        ..onJson(
          'POST',
          ApiPaths.refresh,
          tokenPairJson(access: 'a-2', refresh: null),
        )
        ..onJson('GET', ApiPaths.me, meJson())
        ..on('POST', ApiPaths.logout, (_) => const FakeReply.noContent());
      container = backend.container()..read(authControllerProvider);
      await auth().restore();
      expect(
        backend.adapter.requests,
        isEmpty,
      ); // no marker: nothing to restore

      await auth().login(email: 'ana@example.com', password: 'correct horse');

      final login = backend.adapter.requestsTo('POST', ApiPaths.login).single;
      expect(login.options.headers[refreshTransportHeader], 'cookie');
      expect(backend.prefs.data.values, [true]);
      expect(backend.store.refreshToken, isNull);

      // A reload: a new app on the same storage restores through the cookie.
      final reloaded = backend.container()..read(authControllerProvider);
      await reloaded.read(authControllerProvider.notifier).restore();
      expect(reloaded.read(authControllerProvider), isA<Authenticated>());
      final refresh = backend.adapter
          .requestsTo('POST', ApiPaths.refresh)
          .single;
      expect(refresh.jsonMap, {'refresh_token': null});
      expect(refresh.options.headers[refreshTransportHeader], 'cookie');

      await reloaded.read(authControllerProvider.notifier).logout();
      final logout = backend.adapter.requestsTo('POST', ApiPaths.logout).single;
      expect(logout.jsonMap, {'refresh_token': null});
      expect(backend.prefs.data, isEmpty);
    });

    test('a token from before cookie mode moves into the cookie', () async {
      backend = TestBackend(
        storedRefreshToken: 'refresh-legacy',
        cookieMode: true,
      );
      backend.adapter
        ..onJson('POST', ApiPaths.refresh, tokenPairJson(refresh: null))
        ..onJson('GET', ApiPaths.me, meJson());
      container = backend.container()..read(authControllerProvider);

      await auth().restore();

      expect(container.read(authControllerProvider), isA<Authenticated>());
      final refresh = backend.adapter
          .requestsTo('POST', ApiPaths.refresh)
          .single;
      expect(refresh.jsonMap, {'refresh_token': 'refresh-legacy'});
      expect(refresh.options.headers[refreshTransportHeader], 'cookie');
      expect(backend.store.refreshToken, isNull);
      expect(backend.prefs.data.values, [true]);
    });
  });
}
