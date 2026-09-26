import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;
  late ProviderContainer container;

  AuthState state() => container.read(authControllerProvider);
  AuthController auth() => container.read(authControllerProvider.notifier);

  /// Builds the controller and waits for its startup restore.
  Future<void> restore() async {
    container.read(authControllerProvider);
    await auth().restore();
  }

  /// A signed-in container: stored session restored with `access-1`.
  Future<void> signIn({int accessExpiresIn = 900}) async {
    backend = TestBackend(storedRefreshToken: 'refresh-0');
    backend.adapter
      ..onJson(
        'POST',
        ApiPaths.refresh,
        tokenPairJson(expiresIn: accessExpiresIn),
      )
      ..onJson('GET', ApiPaths.me, meJson());
    container = backend.container();
    await restore();
    expect(state(), isA<Authenticated>());
  }

  group('restore', () {
    test('refreshes, then loads /me', () async {
      backend = TestBackend(storedRefreshToken: 'refresh-0')..stubRestore();
      container = backend.container();

      expect(state(), const AuthUnknown());
      await restore();

      expect(state(), isA<Authenticated>());
      expect(container.read(currentUserProvider)?.displayName, 'Ana');
      expect(container.read(currentUserIdProvider), meJson()['id']);
      expect(backend.refreshCount, 1);
      expect(
        backend.adapter.requestsTo('POST', ApiPaths.refresh).single.jsonMap,
        {'refresh_token': 'refresh-0'},
      );
      expect(
        backend.adapter.requestsTo('GET', ApiPaths.me).single.authorization,
        'Bearer access-1',
      );
      expect(backend.store.refreshToken, 'refresh-1');
    });

    test('runs once on startup', () async {
      backend = TestBackend(storedRefreshToken: 'refresh-0')..stubRestore();
      container = backend.container()..read(authControllerProvider);
      await pumpEventQueue();

      expect(state(), isA<Authenticated>());
      expect(backend.refreshCount, 1);
    });

    test('without a stored session: signed out, no requests', () async {
      backend = TestBackend();
      container = backend.container();

      await restore();

      expect(state(), const Unauthenticated(SignOutReason.noSession));
      expect(backend.adapter.requests, isEmpty);
    });

    test('a network failure keeps the session and waits for Retry', () async {
      backend = TestBackend(storedRefreshToken: 'refresh-0');
      backend.adapter.on(
        'POST',
        ApiPaths.refresh,
        (_) => const FakeReply.networkError(),
      );
      container = backend.container();

      await restore();

      expect(
        state(),
        isA<AuthUnknown>().having(
          (s) => s.error,
          'error',
          isA<NetworkException>(),
        ),
      );
      expect(backend.store.refreshToken, 'refresh-0');

      // The server is back: Retry.
      backend.stubRestore();
      await auth().restore();

      expect(state(), isA<Authenticated>());
    });

    test('a 5xx on /me keeps the session', () async {
      backend = TestBackend(storedRefreshToken: 'refresh-0')..stubRestore();
      backend.adapter.on(
        'GET',
        ApiPaths.me,
        (_) => FakeReply.problem(500, ErrorCodes.internalError),
      );
      container = backend.container();

      await restore();

      expect(state(), isA<AuthUnknown>());
      expect((state() as AuthUnknown).error, isA<ProblemException>());
      expect(backend.store.refreshToken, 'refresh-1');
    });

    test('a rejected refresh token signs out and clears it', () async {
      backend = TestBackend(storedRefreshToken: 'refresh-0');
      backend.adapter.onProblem(
        'POST',
        ApiPaths.refresh,
        401,
        ErrorCodes.refreshInvalid,
      );
      container = backend.container();

      await restore();

      expect(state(), const Unauthenticated(SignOutReason.sessionExpired));
      expect(backend.store.refreshToken, isNull);
      expect(backend.holder.accessToken, isNull);
    });
  });

  group('login', () {
    setUp(() async {
      backend = TestBackend();
      container = backend.container();
      await restore();
    });

    test('stores the tokens and signs in', () async {
      backend.adapter.onJson(
        'POST',
        ApiPaths.login,
        authSessionJson(
          tokens: tokenPairJson(access: 'a-9', refresh: 'r-9'),
        ),
      );

      final session = await auth().login(
        email: ' ana@example.com ',
        password: 'correct horse',
      );

      expect(session.joinedGroup, isNull);
      expect(state(), isA<Authenticated>());
      expect(backend.adapter.last.jsonMap, {
        'email': 'ana@example.com',
        'password': 'correct horse',
        'device_label': 'web',
      });
      expect(backend.holder.accessToken, 'a-9');
      expect(backend.store.refreshToken, 'r-9');
    });

    test('wrong credentials throw and stay signed out', () async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.login,
        401,
        ErrorCodes.invalidCredentials,
      );

      await expectLater(
        auth().login(email: 'ana@example.com', password: 'nope'),
        throwsA(
          isA<ProblemException>().having(
            (e) => e.code,
            'code',
            ErrorCodes.invalidCredentials,
          ),
        ),
      );
      expect(state(), const Unauthenticated(SignOutReason.noSession));
      expect(backend.refreshCount, 0);
    });
  });

  group('register', () {
    setUp(() async {
      backend = TestBackend();
      container = backend.container();
      await restore();
      backend.adapter.onJson(
        'POST',
        ApiPaths.register,
        authSessionJson(joinedGroup: groupSummaryJson()),
        status: 201,
      );
    });

    test(
      'sends the device label, timezone and normalized invite code',
      () async {
        final session = await auth().register(
          displayName: ' Ana ',
          email: 'ana@example.com',
          password: 'long enough password',
          inviteCode: ' abcd-efgh-ik ',
        );

        expect(backend.adapter.last.jsonMap, {
          'email': 'ana@example.com',
          'password': 'long enough password',
          'display_name': 'Ana',
          'timezone': 'Europe/Bucharest',
          'device_label': 'web',
          'invite_code': 'ABCDEFGH1K',
        });
        expect(session.joinedGroup?.name, 'Movie night');
        expect(state(), isA<Authenticated>());
        expect(backend.store.refreshToken, 'refresh-1');
      },
    );

    test('accepts a pasted join link', () async {
      await auth().register(
        displayName: 'Ana',
        email: 'ana@example.com',
        password: 'long enough password',
        inviteCode: 'https://friends.example.com/join/abcde-fghjk',
      );

      expect(backend.adapter.last.jsonMap['invite_code'], 'ABCDEFGHJK');
    });

    test('sends a null invite code when there is none', () async {
      await auth().register(
        displayName: 'Ana',
        email: 'ana@example.com',
        password: 'long enough password',
        inviteCode: '  ',
      );

      final body = backend.adapter.last.jsonMap;
      expect(body.containsKey('invite_code'), isTrue);
      expect(body['invite_code'], isNull);
    });
  });

  group('signed in', () {
    test('logout clears the tokens and revokes on the server', () async {
      await signIn();
      backend.adapter.on(
        'POST',
        ApiPaths.logout,
        (_) => const FakeReply.noContent(),
      );

      await auth().logout();

      final logout = backend.adapter.requestsTo('POST', ApiPaths.logout);
      expect(logout.single.jsonMap, {'refresh_token': 'refresh-1'});
      expect(logout.single.authorization, isNull);
      expect(state(), const Unauthenticated(SignOutReason.signedOut));
      expect(backend.store.refreshToken, isNull);
      expect(backend.holder.accessToken, isNull);
    });

    test('logout signs out locally before the server answers', () async {
      await signIn();
      final serverGate = Completer<void>();
      backend.adapter.on('POST', ApiPaths.logout, (_) async {
        await serverGate.future;
        return const FakeReply.noContent();
      });

      final logout = auth().logout();
      await pumpEventQueue();

      expect(state(), const Unauthenticated(SignOutReason.signedOut));
      expect(backend.store.refreshToken, isNull);
      expect(backend.holder.accessToken, isNull);
      expect(backend.adapter.requestsTo('POST', ApiPaths.logout), hasLength(1));

      serverGate.complete();
      await logout;
    });

    test('public calls do not wait behind a pending token refresh', () async {
      // The access token expires within 30 s: the next protected call
      // refreshes first, and that refresh hangs (slow network).
      await signIn(accessExpiresIn: 20);
      final refreshGate = Completer<void>();
      final refreshesBefore = backend.refreshCount;
      backend.adapter
        ..on('POST', ApiPaths.refresh, (_) async {
          await refreshGate.future;
          return FakeReply.json(tokenPairJson(access: 'access-2'));
        })
        ..onJson('GET', ApiPaths.groups, <Object?>[])
        ..on('POST', ApiPaths.logout, (_) => const FakeReply.noContent())
        ..onJson('POST', ApiPaths.login, authSessionJson());
      final groups = apiCall(container.read(groupsClientProvider).listGroups);
      await pumpEventQueue();
      expect(backend.refreshCount, refreshesBefore + 1); // pending

      // Neither waits for the refresh (the auth interceptor queues requests
      // while it refreshes; public calls don't go through it).
      await auth().logout().timeout(const Duration(seconds: 5));
      expect(backend.adapter.requestsTo('POST', ApiPaths.logout), hasLength(1));
      await auth()
          .login(email: 'ana@example.com', password: 'password12')
          .timeout(const Duration(seconds: 5));
      expect(state(), isA<Authenticated>());
      final public = [
        ...backend.adapter.requestsTo('POST', ApiPaths.logout),
        ...backend.adapter.requestsTo('POST', ApiPaths.login),
      ];
      expect(public.map((r) => r.authorization), everyElement(isNull));

      refreshGate.complete();
      await groups;
    });

    test('logout works offline', () async {
      await signIn();
      backend.adapter.on(
        'POST',
        ApiPaths.logout,
        (_) => const FakeReply.networkError(),
      );

      await auth().logout();

      expect(state(), const Unauthenticated(SignOutReason.signedOut));
      expect(backend.store.refreshToken, isNull);
    });

    test('logoutAll signs out after the server confirms', () async {
      await signIn();
      backend.adapter.on(
        'POST',
        ApiPaths.logoutAll,
        (_) => const FakeReply.noContent(),
      );

      await auth().logoutAll();

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.logoutAll)
            .single
            .authorization,
        'Bearer access-1',
      );
      expect(state(), const Unauthenticated(SignOutReason.signedOut));
    });

    test('logoutAll offline throws and stays signed in', () async {
      await signIn();
      backend.adapter.on(
        'POST',
        ApiPaths.logoutAll,
        (_) => const FakeReply.networkError(),
      );

      await expectLater(auth().logoutAll(), throwsA(isA<NetworkException>()));
      expect(state(), isA<Authenticated>());
      expect(backend.store.refreshToken, 'refresh-1');
    });

    test('updateMe sends the complete profile and replaces the user', () async {
      await signIn();
      backend.adapter.onJson(
        'PUT',
        ApiPaths.me,
        meJson(
          displayName: 'Ana Maria',
          birthday: {'month': 2, 'day': 29, 'year': null},
        ),
      );

      await auth().updateMe(
        const MeUpdate(
          displayName: 'Ana Maria',
          timezone: 'Europe/Bucharest',
          birthday: Birthday(month: 2, day: 29),
        ),
      );

      expect(backend.adapter.last.jsonMap, {
        'display_name': 'Ana Maria',
        'birthday': {'month': 2, 'day': 29, 'year': null},
        'timezone': 'Europe/Bucharest',
        'locale': null,
        'avatar_url': null,
      });
      expect(container.read(currentUserProvider)?.displayName, 'Ana Maria');
    });

    test('changePassword keeps this session with the returned pair', () async {
      await signIn();
      backend.adapter.onJson(
        'POST',
        ApiPaths.password,
        tokenPairJson(access: 'access-pw', refresh: 'refresh-pw'),
      );

      await auth().changePassword(
        currentPassword: 'old password',
        newPassword: 'new password!',
      );

      expect(backend.adapter.last.jsonMap, {
        'current_password': 'old password',
        'new_password': 'new password!',
      });
      expect(backend.holder.accessToken, 'access-pw');
      expect(backend.store.refreshToken, 'refresh-pw');
      expect(state(), isA<Authenticated>());
    });

    test('changePassword with a wrong password stays signed in', () async {
      await signIn();
      backend.adapter.onProblem(
        'POST',
        ApiPaths.password,
        422,
        ErrorCodes.wrongPassword,
        errors: [
          {
            'field': 'current_password',
            'message': 'Wrong password.',
            'type': 'wrong_password',
          },
        ],
      );

      await expectLater(
        auth().changePassword(currentPassword: 'x', newPassword: 'y' * 10),
        throwsA(isA<ProblemException>()),
      );
      expect(state(), isA<Authenticated>());
      expect(backend.store.refreshToken, 'refresh-1');
    });

    test('deleteAccount confirms with the password and signs out', () async {
      await signIn();
      backend.adapter.on(
        'POST',
        ApiPaths.deletion,
        (_) => const FakeReply.noContent(),
      );

      await auth().deleteAccount(password: 'my password');

      expect(backend.adapter.last.jsonMap, {'password': 'my password'});
      expect(state(), const Unauthenticated(SignOutReason.accountDeleted));
      expect(backend.store.refreshToken, isNull);
    });

    test('a 401 unauthenticated on any call ends the session', () async {
      await signIn();
      backend.adapter.onProblem(
        'GET',
        ApiPaths.groups,
        401,
        ErrorCodes.unauthenticated,
      );

      await expectLater(
        apiCall(container.read(groupsClientProvider).listGroups),
        throwsA(isA<ProblemException>()),
      );

      expect(state(), const Unauthenticated(SignOutReason.sessionExpired));
      expect(backend.store.refreshToken, isNull);
    });

    test('a 401 without a problem body keeps the session', () async {
      await signIn();
      backend.adapter.on(
        'GET',
        ApiPaths.groups,
        (_) => const FakeReply.text(
          '<html>401 Authorization Required</html>',
          status: 401,
        ),
      );

      await expectLater(
        apiCall(container.read(groupsClientProvider).listGroups),
        throwsA(isA<UnexpectedApiException>()),
      );

      expect(state(), isA<Authenticated>());
      expect(backend.store.refreshToken, 'refresh-1');
    });

    test(
      'an expired access token is refreshed once, without a logout',
      () async {
        // The manual check of issue #3 with ACCESS_TOKEN_TTL_MINUTES=1.
        await signIn(accessExpiresIn: 60);
        backend.adapter
          ..onJson('GET', ApiPaths.groups, <Object?>[])
          ..onJson(
            'POST',
            ApiPaths.refresh,
            tokenPairJson(
              access: 'access-2',
              refresh: 'refresh-2',
              expiresIn: 60,
            ),
          );
        backend.clock.advance(const Duration(minutes: 2));

        final groups = container.read(groupsClientProvider);
        await Future.wait([
          for (var i = 0; i < 3; i++) apiCall(groups.listGroups),
        ]);

        expect(backend.refreshCount, 2); // restore + one refresh
        expect(state(), isA<Authenticated>());
        final calls = backend.adapter.requestsTo('GET', ApiPaths.groups);
        expect(calls, hasLength(3));
        expect(calls.map((r) => r.authorization).toSet(), {'Bearer access-2'});
        expect(backend.store.refreshToken, 'refresh-2');
      },
    );

    test('network errors never sign out', () async {
      await signIn();
      backend.adapter.on(
        'GET',
        ApiPaths.groups,
        (_) => const FakeReply.networkError(),
      );

      await expectLater(
        apiCall(container.read(groupsClientProvider).listGroups),
        throwsA(isA<NetworkException>()),
      );

      expect(state(), isA<Authenticated>());
      expect(backend.store.refreshToken, 'refresh-1');
    });
  });

  group('currentUserIdProvider', () {
    test('data providers that watch it reset on logout and account '
        'switch', () async {
      await signIn();
      var fetches = 0;
      backend.adapter
        ..on('GET', ApiPaths.groups, (_) {
          fetches++;
          return FakeReply.json([groupSummaryJson(name: 'Fetch $fetches')]);
        })
        ..on('POST', ApiPaths.logout, (_) => const FakeReply.noContent())
        ..onJson(
          'POST',
          ApiPaths.login,
          authSessionJson(
            user: meJson(id: '0190c3a5-0000-7000-8000-000000000002'),
            tokens: tokenPairJson(access: 'access-bob'),
          ),
        );
      // The pattern every data provider follows (see currentUserIdProvider).
      final groupsProvider = FutureProvider<List<GroupSummary>>((ref) {
        ref.watch(currentUserIdProvider);
        return apiCall(ref.watch(groupsClientProvider).listGroups);
      });

      final first = await container.read(groupsProvider.future);
      expect(first.single.name, 'Fetch 1');
      // Cached while the same user stays signed in.
      expect(await container.read(groupsProvider.future), same(first));

      await auth().logout();
      await auth().login(email: 'bob@example.com', password: 'password12');

      final second = await container.read(groupsProvider.future);
      expect(second.single.name, 'Fetch 2');
      expect(
        backend.adapter.requestsTo('GET', ApiPaths.groups).last.authorization,
        'Bearer access-bob',
      );
    });
  });
}
