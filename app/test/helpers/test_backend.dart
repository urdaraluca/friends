import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:friends/core/device/device_info.dart';
import 'package:friends/core/network/dio_provider.dart';

import 'api_fixtures.dart';
import 'fake_http_adapter.dart';

/// A [TokenStore] in memory.
class InMemoryTokenStore implements TokenStore {
  new([this.refreshToken]);

  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String refreshToken) async =>
      this.refreshToken = refreshToken;

  @override
  Future<void> clear() async => refreshToken = null;
}

/// A clock tests move by hand.
class FakeClock {
  new([DateTime? now]) : now = now ?? DateTime.utc(2026, 10);

  DateTime now;

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

/// The app's real network and auth stack (Dio, interceptors, refresher,
/// generated clients, `AuthController`) wired to a [FakeHttpClientAdapter],
/// an [InMemoryTokenStore] and a [FakeClock].
///
/// ```dart
/// final backend = TestBackend(storedRefreshToken: 'refresh-0')
///   ..stubRestore();
/// final container = backend.container();
/// ```
///
/// Pass a [store] to share it between two backends: two browser tabs share
/// one refresh token (local storage) but each has its own access token.
class TestBackend {
  new({String? storedRefreshToken, InMemoryTokenStore? store})
    : store = store ?? InMemoryTokenStore(storedRefreshToken);

  final adapter = FakeHttpClientAdapter();
  final InMemoryTokenStore store;
  final clock = FakeClock();
  late final holder = TokenHolder(clock: clock.call);

  /// Overrides for a `ProviderScope` or `ProviderContainer`.
  List<Override> get overrides => [
    apiBaseUrlProvider.overrideWithValue('http://api.test'),
    httpClientAdapterProvider.overrideWithValue(adapter),
    tokenStoreProvider.overrideWithValue(store),
    tokenHolderProvider.overrideWithValue(holder),
    deviceLabelProvider.overrideWithValue('web'),
    deviceTimezoneProvider.overrideWith((ref) async => 'Europe/Bucharest'),
  ];

  /// A container disposed at the end of the test.
  ProviderContainer container() => ProviderContainer.test(overrides: overrides);

  /// `POST /auth/refresh` answers with a new pair, `GET /me` with [me].
  void stubRestore({Map<String, Object?>? me}) {
    adapter
      ..onJson('POST', ApiPaths.refresh, tokenPairJson())
      ..onJson('GET', ApiPaths.me, me ?? meJson());
  }

  /// Number of `POST /auth/refresh` calls so far.
  int get refreshCount => adapter.requestsTo('POST', ApiPaths.refresh).length;
}
