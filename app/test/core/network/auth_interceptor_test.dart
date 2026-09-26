import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/token_holder.dart';
import 'package:friends/core/auth/token_refresher.dart';
import 'package:friends/core/network/auth_interceptor.dart';
import 'package:friends/core/network/dio_provider.dart';
import 'package:friends/core/network/problem_interceptor.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/test_backend.dart';

void main() {
  late FakeHttpClientAdapter adapter;
  late InMemoryTokenStore store;
  late FakeClock clock;
  late TokenHolder holder;
  late int sessionExpiredCalls;
  late FriendsApi api;

  setUp(() {
    adapter = FakeHttpClientAdapter();
    store = InMemoryTokenStore('refresh-0');
    clock = FakeClock();
    holder = TokenHolder(clock: clock.call)
      ..set('access-0', expiresIn: const Duration(minutes: 15));
    sessionExpiredCalls = 0;
    void onSessionExpired() => sessionExpiredCalls++;

    final bareDio = Dio(apiBaseOptions('http://api.test'))
      ..httpClientAdapter = adapter;
    final refresher = TokenRefresher(
      authClient: AuthClient(bareDio),
      store: store,
      holder: holder,
      onSessionExpired: onSessionExpired,
    );
    final dio = Dio(apiBaseOptions('http://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.addAll([
        AuthInterceptor(
          tokens: holder,
          refresher: refresher,
          retryDio: bareDio,
          onSessionExpired: onSessionExpired,
        ),
        ProblemInterceptor(),
      ]);
    api = FriendsApi(dio);
  });

  List<RecordedRequest> meCalls() => adapter.requestsTo('GET', ApiPaths.me);
  int refreshCount() => adapter.requestsTo('POST', ApiPaths.refresh).length;

  /// `GET /me` accepts only `Bearer <validToken>`, else `401 token_expired`.
  void meAccepts(String validToken) {
    adapter.on('GET', ApiPaths.me, (request) {
      return request.authorization == 'Bearer $validToken'
          ? FakeReply.json(meJson())
          : FakeReply.problem(401, ErrorCodes.tokenExpired);
    });
  }

  void refreshGives(String access, {Future<void>? after}) {
    adapter.on('POST', ApiPaths.refresh, (_) async {
      await after;
      return FakeReply.json(tokenPairJson(access: access, refresh: 'r-new'));
    });
  }

  group('AuthInterceptor', () {
    test('attaches the access token to protected calls', () async {
      meAccepts('access-0');

      await apiCall(api.users.getMe);

      expect(meCalls().single.authorization, 'Bearer access-0');
      expect(refreshCount(), 0);
    });

    test('skips public calls', () async {
      adapter
        ..onJson('POST', ApiPaths.login, authSessionJson())
        ..onJson('POST', ApiPaths.register, authSessionJson(), status: 201)
        ..onJson('POST', ApiPaths.refresh, tokenPairJson())
        ..on('POST', ApiPaths.logout, (_) => const FakeReply.noContent())
        ..onJson('GET', '/api/v1/invites/ABCDEFGHJK', {
          'code': 'ABCDEFGHJK',
          'status': 'valid',
          'group': {
            'name': 'G',
            'emoji': null,
            'color': null,
            'member_count': 1,
          },
          'invited_by_name': 'Ana',
          'expires_at': null,
        })
        ..onJson('GET', ApiPaths.health, {
          'status': 'ok',
          'version': '1',
          'db': 'ok',
        });

      await api.auth.login(
        body: const LoginRequest(email: 'a@example.com', password: 'pw'),
      );
      await api.auth.register(
        body: const RegisterRequest(
          email: 'a@example.com',
          password: 'long-enough-pw',
          displayName: 'A',
        ),
      );
      await api.auth.refreshTokens(
        body: const RefreshRequest(refreshToken: 'x'),
      );
      await api.auth.logout(body: const RefreshRequest(refreshToken: 'x'));
      await api.invites.previewInvite(code: 'ABCDEFGHJK');
      await api.health.getHealth();

      expect(adapter.requests, hasLength(6));
      for (final request in adapter.requests) {
        expect(request.authorization, isNull, reason: '$request');
        expect(
          request.options.extra[PublicEndpoints.extraKey],
          isTrue,
          reason: '$request',
        );
      }
    });

    test('does not treat logout-all or invite accept as public', () async {
      adapter
        ..on('POST', ApiPaths.logoutAll, (_) => const FakeReply.noContent())
        ..onJson(
          'POST',
          '/api/v1/invites/ABCDEFGHJK/accept',
          groupSummaryJson()..addAll({
            'description': null,
            'currency': 'EUR',
            'timezone': 'UTC',
            'members_can_invite': true,
            'created_by': null,
            'updated_at': '2026-09-01T10:00:00Z',
          }),
        );

      await api.auth.logoutAll();
      await api.invites.acceptInvite(code: 'ABCDEFGHJK');

      for (final request in adapter.requests) {
        expect(request.authorization, 'Bearer access-0', reason: '$request');
      }
    });

    test('a 401 on a public call neither refreshes nor signs out', () async {
      adapter.onProblem(
        'POST',
        ApiPaths.login,
        401,
        ErrorCodes.invalidCredentials,
      );

      await expectLater(
        apiCall(
          () => api.auth.login(
            body: const LoginRequest(email: 'a@example.com', password: 'x'),
          ),
        ),
        throwsA(
          isA<ProblemException>().having(
            (e) => e.code,
            'code',
            ErrorCodes.invalidCredentials,
          ),
        ),
      );
      expect(refreshCount(), 0);
      expect(sessionExpiredCalls, 0);
    });

    test('5 concurrent 401 token_expired cause exactly one refresh', () async {
      final refreshGate = Completer<void>();
      meAccepts('access-1');
      refreshGives('access-1', after: refreshGate.future);

      final calls = [for (var i = 0; i < 5; i++) apiCall(api.users.getMe)];
      await pumpEventQueue();
      refreshGate.complete();
      final results = await Future.wait(calls);

      expect(results, hasLength(5));
      expect(refreshCount(), 1);
      final retries = meCalls().where(
        (r) => r.authorization == 'Bearer access-1',
      );
      expect(retries, hasLength(5));
      expect(
        retries.every(
          (r) => r.options.extra[AuthInterceptor.retriedKey] == true,
        ),
        isTrue,
      );
      expect(sessionExpiredCalls, 0);
      expect(store.refreshToken, 'r-new');
    });

    test('a request that used an older token is retried without a new '
        'refresh', () async {
      meAccepts('access-1');
      // Another request already refreshed after this one was sent.
      adapter.on('GET', ApiPaths.me, (request) {
        if (request.authorization == 'Bearer access-0') {
          holder.set('access-1', expiresIn: const Duration(minutes: 15));
          return FakeReply.problem(401, ErrorCodes.tokenExpired);
        }
        return FakeReply.json(meJson());
      });

      await apiCall(api.users.getMe);

      expect(refreshCount(), 0);
      expect(meCalls().map((r) => r.authorization), [
        'Bearer access-0',
        'Bearer access-1',
      ]);
    });

    test('retries exactly once', () async {
      adapter.onProblem('GET', ApiPaths.me, 401, ErrorCodes.tokenExpired);
      refreshGives('access-1');

      await expectLater(
        apiCall(api.users.getMe),
        throwsA(
          isA<ProblemException>().having(
            (e) => e.code,
            'code',
            ErrorCodes.tokenExpired,
          ),
        ),
      );

      expect(meCalls(), hasLength(2));
      expect(refreshCount(), 1);
      expect(sessionExpiredCalls, 0);
    });

    test('refreshes proactively when the token expires within 30 s', () async {
      holder.set('access-0', expiresIn: const Duration(seconds: 20));
      meAccepts('access-1');
      refreshGives('access-1');

      await apiCall(api.users.getMe);

      expect(refreshCount(), 1);
      expect(adapter.requests.first.path, ApiPaths.refresh);
      expect(meCalls().single.authorization, 'Bearer access-1');
    });

    test('does not refresh a token with more than 30 s left', () async {
      holder.set('access-0', expiresIn: const Duration(seconds: 45));
      meAccepts('access-0');

      await apiCall(api.users.getMe);
      clock.advance(const Duration(seconds: 20));
      meAccepts('access-1');
      refreshGives('access-1');
      await apiCall(api.users.getMe);

      expect(refreshCount(), 1);
      expect(meCalls().map((r) => r.authorization), [
        'Bearer access-0',
        'Bearer access-1',
      ]);
    });

    test(
      'a failed proactive refresh keeps using a still-valid token',
      () async {
        holder.set('access-0', expiresIn: const Duration(seconds: 20));
        meAccepts('access-0');
        adapter.onProblem(
          'POST',
          ApiPaths.refresh,
          429,
          ErrorCodes.rateLimited,
        );

        await apiCall(api.users.getMe);

        expect(meCalls().single.authorization, 'Bearer access-0');
        expect(sessionExpiredCalls, 0);
      },
    );

    for (final code in [
      ErrorCodes.unauthenticated,
      ErrorCodes.refreshInvalid,
      ErrorCodes.refreshReuseDetected,
    ]) {
      test('a 401 $code ends the session without a refresh', () async {
        adapter.onProblem('GET', ApiPaths.me, 401, code);

        await expectLater(
          apiCall(api.users.getMe),
          throwsA(isA<ProblemException>()),
        );

        expect(sessionExpiredCalls, 1);
        expect(refreshCount(), 0);
        expect(meCalls(), hasLength(1));
      });
    }

    group('a 401 that is not problem+json (a proxy, not the API)', () {
      const authWall = FakeReply.text(
        '<html>401 Authorization Required</html>',
        status: 401,
      );

      test('neither refreshes nor signs out', () async {
        adapter.on('GET', ApiPaths.me, (_) => authWall);

        await expectLater(
          apiCall(api.users.getMe),
          throwsA(
            isA<UnexpectedApiException>().having(
              (e) => e.statusCode,
              'statusCode',
              401,
            ),
          ),
        );

        expect(sessionExpiredCalls, 0);
        expect(refreshCount(), 0);
        expect(store.refreshToken, 'refresh-0');
        expect(holder.accessToken, 'access-0');
      });

      test('on the retry, does not sign out either', () async {
        adapter.on('GET', ApiPaths.me, (request) {
          return request.authorization == 'Bearer access-0'
              ? FakeReply.problem(401, ErrorCodes.tokenExpired)
              : authWall;
        });
        refreshGives('access-1');

        await expectLater(
          apiCall(api.users.getMe),
          throwsA(isA<UnexpectedApiException>()),
        );

        expect(meCalls(), hasLength(2));
        expect(sessionExpiredCalls, 0);
        expect(holder.accessToken, 'access-1');
      });
    });

    test('a late 401 for an older session is ignored', () async {
      adapter.on('GET', ApiPaths.me, (_) {
        // Someone else signed in while this request was in flight.
        holder.set('other-account', expiresIn: const Duration(minutes: 15));
        return FakeReply.problem(401, ErrorCodes.unauthenticated);
      });

      await expectLater(
        apiCall(api.users.getMe),
        throwsA(isA<ProblemException>()),
      );

      expect(sessionExpiredCalls, 0);
    });

    test('a refresh rejected with 401 ends the session', () async {
      adapter
        ..onProblem('GET', ApiPaths.me, 401, ErrorCodes.tokenExpired)
        ..onProblem('POST', ApiPaths.refresh, 401, ErrorCodes.refreshInvalid);

      await expectLater(
        apiCall(api.users.getMe),
        throwsA(
          isA<ProblemException>().having(
            (e) => e.code,
            'code',
            ErrorCodes.refreshInvalid,
          ),
        ),
      );

      expect(sessionExpiredCalls, 1);
      expect(store.refreshToken, isNull);
      expect(holder.accessToken, isNull);
    });

    group('requests stamped for one account (AccountStampInterceptor)', () {
      late String? signedInUser;
      late List<String> accountChanges;
      late FriendsApi stamped;

      setUp(() {
        signedInUser = 'yan';
        accountChanges = [];
        holder.set(fakeJwt(sub: 'yan'), expiresIn: const Duration(minutes: 15));
        final bareDio = Dio(apiBaseOptions('http://api.test'))
          ..httpClientAdapter = adapter;
        final refresher = TokenRefresher(
          authClient: AuthClient(bareDio),
          store: store,
          holder: holder,
          onSessionExpired: () => sessionExpiredCalls++,
        );
        final dio = Dio(apiBaseOptions('http://api.test'))
          ..httpClientAdapter = adapter
          ..interceptors.addAll([
            AccountStampInterceptor(() => signedInUser),
            AuthInterceptor(
              tokens: holder,
              refresher: refresher,
              retryDio: bareDio,
              onSessionExpired: () => sessionExpiredCalls++,
              onAccountChanged: accountChanges.add,
            ),
            ProblemInterceptor(),
          ]);
        stamped = FriendsApi(dio);
      });

      /// Another tab signed in as Xena: a refresh returns her token.
      void refreshGivesXena() => adapter.onJson(
        'POST',
        ApiPaths.refresh,
        tokenPairJson(access: fakeJwt(sub: 'xena')),
      );

      Matcher throwsAccountChanged() =>
          throwsA(same(AuthInterceptor.accountChangedError));

      test('go out with a token of that account', () async {
        adapter.onJson('GET', ApiPaths.me, meJson());

        await apiCall(stamped.users.getMe);

        expect(meCalls().single.authorization, 'Bearer ${fakeJwt(sub: 'yan')}');
        expect(
          meCalls().single.options.extra[AccountStampInterceptor.extraKey],
          'yan',
        );
        expect(accountChanges, isEmpty);
      });

      test('are never sent with the token of another account', () async {
        holder.set(fakeJwt(sub: 'yan'), expiresIn: const Duration(seconds: 5));
        refreshGivesXena();

        await expectLater(apiCall(stamped.users.getMe), throwsAccountChanged());

        expect(meCalls(), isEmpty);
        expect(accountChanges, ['xena']);
        expect(sessionExpiredCalls, 0);
      });

      test('are never retried with the token of another account', () async {
        adapter.onProblem('GET', ApiPaths.me, 401, ErrorCodes.tokenExpired);
        refreshGivesXena();

        await expectLater(apiCall(stamped.users.getMe), throwsAccountChanged());

        expect(meCalls(), hasLength(1));
        expect(accountChanges, ['xena']);
        expect(sessionExpiredCalls, 0);
      });

      test(
        'unstamped requests (signed out or restoring) take any token',
        () async {
          signedInUser = null;
          holder.set(
            fakeJwt(sub: 'xena'),
            expiresIn: const Duration(minutes: 1),
          );
          adapter.onJson('GET', ApiPaths.me, meJson());

          await apiCall(stamped.users.getMe);

          expect(meCalls(), hasLength(1));
          expect(accountChanges, isEmpty);
        },
      );
    });

    group('network errors never sign the user out', () {
      test('on the request itself', () async {
        adapter.on('GET', ApiPaths.me, (_) => const FakeReply.networkError());

        await expectLater(
          apiCall(api.users.getMe),
          throwsA(isA<NetworkException>()),
        );

        expect(sessionExpiredCalls, 0);
        expect(store.refreshToken, 'refresh-0');
        expect(holder.accessToken, 'access-0');
      });

      test('on the refresh after a 401 token_expired', () async {
        adapter
          ..onProblem('GET', ApiPaths.me, 401, ErrorCodes.tokenExpired)
          ..on('POST', ApiPaths.refresh, (_) => const FakeReply.networkError());

        await expectLater(
          apiCall(api.users.getMe),
          throwsA(isA<NetworkException>()),
        );

        expect(sessionExpiredCalls, 0);
        expect(store.refreshToken, 'refresh-0');
      });

      test('on a proactive refresh of an expired token', () async {
        holder.set('access-0', expiresIn: Duration.zero);
        adapter.on('POST', ApiPaths.refresh, (_) => const FakeReply.timeout());

        await expectLater(
          apiCall(api.users.getMe),
          throwsA(isA<NetworkException>()),
        );

        expect(meCalls(), isEmpty);
        expect(sessionExpiredCalls, 0);
        expect(store.refreshToken, 'refresh-0');
      });
    });
  });
}
