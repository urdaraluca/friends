import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/clients/auth_client.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_refresher.dart';
import 'package:friends/core/auth/token_store.dart';
import 'package:friends/core/network/dio_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/test_backend.dart';

class _MockTokenStore extends Mock implements TokenStore;

void main() {
  late FakeHttpClientAdapter adapter;
  late InMemoryTokenStore store;
  late TokenHolder holder;
  late int sessionExpiredCalls;
  late TokenRefresher refresher;

  setUp(() {
    adapter = FakeHttpClientAdapter();
    store = InMemoryTokenStore('refresh-0');
    holder = TokenHolder()
      ..set('access-0', expiresIn: const Duration(minutes: 15));
    sessionExpiredCalls = 0;
    final dio = Dio(apiBaseOptions('http://api.test'))
      ..httpClientAdapter = adapter;
    refresher = TokenRefresher(
      authClient: AuthClient(dio),
      store: store,
      holder: holder,
      onSessionExpired: () => sessionExpiredCalls++,
    );
  });

  List<RecordedRequest> refreshCalls() =>
      adapter.requestsTo('POST', ApiPaths.refresh);

  group('TokenRefresher', () {
    test('stores the new pair', () async {
      adapter.onJson('POST', ApiPaths.refresh, tokenPairJson());

      await refresher.refresh();

      expect(refreshCalls().single.jsonMap, {'refresh_token': 'refresh-0'});
      expect(holder.accessToken, 'access-1');
      expect(store.refreshToken, 'refresh-1');
      expect(sessionExpiredCalls, 0);
    });

    test('concurrent callers share exactly one refresh', () async {
      final gate = Completer<void>();
      adapter.on('POST', ApiPaths.refresh, (_) async {
        await gate.future;
        return FakeReply.json(tokenPairJson());
      });

      final calls = List.generate(5, (_) => refresher.refresh());
      await pumpEventQueue();
      gate.complete();
      await Future.wait(calls);

      expect(refreshCalls(), hasLength(1));
      expect(holder.accessToken, 'access-1');

      // The next refresh is a new one.
      await refresher.refresh();
      expect(refreshCalls(), hasLength(2));
    });

    test('re-reads the stored refresh token before each refresh', () async {
      adapter.on('POST', ApiPaths.refresh, (request) {
        final presented = request.jsonMap['refresh_token']! as String;
        return FakeReply.json(
          tokenPairJson(access: 'a-$presented', refresh: 'next-$presented'),
        );
      });

      // Another tab rotated the token after this refresher was created.
      store.refreshToken = 'rotated-elsewhere';
      await refresher.refresh();

      expect(refreshCalls().last.jsonMap['refresh_token'], 'rotated-elsewhere');
      expect(store.refreshToken, 'next-rotated-elsewhere');

      store.refreshToken = 'changed-again';
      await refresher.refresh();

      expect(refreshCalls().last.jsonMap['refresh_token'], 'changed-again');
    });

    test('reads the store right before each POST /auth/refresh', () async {
      final events = <String>[];
      final mockStore = _MockTokenStore();
      var generation = 0;
      when(mockStore.readRefreshToken).thenAnswer((_) async {
        events.add('read');
        return 'stored-${generation++}';
      });
      when(() => mockStore.writeRefreshToken(any())).thenAnswer((_) async {});
      adapter.on('POST', ApiPaths.refresh, (request) {
        events.add('POST ${request.jsonMap['refresh_token']}');
        return FakeReply.json(tokenPairJson());
      });
      final dio = Dio(apiBaseOptions('http://api.test'))
        ..httpClientAdapter = adapter;
      final refresher = TokenRefresher(
        authClient: AuthClient(dio),
        store: mockStore,
        holder: holder,
        onSessionExpired: () => sessionExpiredCalls++,
      );

      await refresher.refresh();
      await refresher.refresh();

      expect(events, ['read', 'POST stored-0', 'read', 'POST stored-1']);
      verify(() => mockStore.writeRefreshToken('refresh-1')).called(2);
      verifyNever(mockStore.clear);
    });

    for (final code in [
      ErrorCodes.refreshInvalid,
      ErrorCodes.refreshReuseDetected,
    ]) {
      test('a 401 $code clears the tokens and ends the session', () async {
        adapter.onProblem('POST', ApiPaths.refresh, 401, code);

        await expectLater(
          refresher.refresh(),
          throwsA(
            isA<ProblemException>()
                .having((e) => e.status, 'status', 401)
                .having((e) => e.code, 'code', code),
          ),
        );

        expect(store.refreshToken, isNull);
        expect(holder.accessToken, isNull);
        expect(sessionExpiredCalls, 1);
      });
    }

    test('a 401 keeps a newer token another tab stored meanwhile', () async {
      adapter.on('POST', ApiPaths.refresh, (request) {
        // Another tab (web: shared storage) changed the password or signed
        // in again while this refresh was in flight.
        store.refreshToken = 'other-tab';
        return FakeReply.problem(401, ErrorCodes.refreshInvalid);
      });

      await expectLater(refresher.refresh(), throwsA(isA<ProblemException>()));

      expect(store.refreshToken, 'other-tab');
      expect(holder.accessToken, isNull);
      expect(sessionExpiredCalls, 1);
    });

    group('clear', () {
      test('deletes the stored token unconditionally by default', () async {
        store.refreshToken = 'never-seen';

        await refresher.clear();

        expect(store.refreshToken, isNull);
        expect(holder.accessToken, isNull);
      });

      test(
        'onlyIfOwn keeps a token this instance never read or saved',
        () async {
          adapter.onJson('POST', ApiPaths.refresh, tokenPairJson());
          await refresher.refresh(); // reads refresh-0, saves refresh-1
          store.refreshToken = 'other-tab';

          await refresher.clear(onlyIfOwn: true);

          expect(store.refreshToken, 'other-tab');
          expect(holder.accessToken, isNull);
        },
      );

      test('onlyIfOwn deletes the token this instance saved', () async {
        adapter.onJson('POST', ApiPaths.refresh, tokenPairJson());
        await refresher.refresh();

        await refresher.clear(onlyIfOwn: true);

        expect(store.refreshToken, isNull);
      });
    });

    test('no stored refresh token ends the session', () async {
      store.refreshToken = null;

      await expectLater(refresher.refresh(), throwsA(isA<ProblemException>()));

      expect(refreshCalls(), isEmpty);
      expect(holder.accessToken, isNull);
      expect(sessionExpiredCalls, 1);
    });

    test('a network error keeps the session', () async {
      adapter.on(
        'POST',
        ApiPaths.refresh,
        (_) => const FakeReply.networkError(),
      );

      await expectLater(refresher.refresh(), throwsA(isA<NetworkException>()));

      expect(store.refreshToken, 'refresh-0');
      expect(holder.accessToken, 'access-0');
      expect(sessionExpiredCalls, 0);
    });

    test('a 429 keeps the session', () async {
      adapter.onProblem('POST', ApiPaths.refresh, 429, ErrorCodes.rateLimited);

      await expectLater(
        refresher.refresh(),
        throwsA(isA<ProblemException>().having((e) => e.status, 'status', 429)),
      );

      expect(store.refreshToken, 'refresh-0');
      expect(sessionExpiredCalls, 0);
    });

    test('a 5xx keeps the session', () async {
      adapter.on(
        'POST',
        ApiPaths.refresh,
        (_) => const FakeReply.text('Bad gateway', status: 502),
      );

      await expectLater(
        refresher.refresh(),
        throwsA(isA<UnexpectedApiException>()),
      );

      expect(store.refreshToken, 'refresh-0');
      expect(sessionExpiredCalls, 0);
    });

    test('a refresh overtaken by a logout does not revive tokens', () async {
      final gate = Completer<void>();
      adapter.on('POST', ApiPaths.refresh, (_) async {
        await gate.future;
        return FakeReply.json(tokenPairJson(access: 'late'));
      });

      final refresh = refresher.refresh();
      await pumpEventQueue();
      await refresher.clear();
      gate.complete();
      await refresh;

      expect(holder.accessToken, isNull);
      expect(store.refreshToken, isNull);
    });
  });
}
