// Web: every browser tab runs its own app (its own AuthController and
// in-memory access token) but they share one stored refresh token (local
// storage). Each TestBackend below is one tab; they share one store.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/access_token.dart';
import 'package:friends/core/auth/auth_controller.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/test_backend.dart';

const _yan = '0190c3a5-0000-7000-8000-00000000000a';
const _xena = '0190c3a5-0000-7000-8000-00000000000b';

/// The user ID in the request's bearer token.
String? userOf(RecordedRequest request) =>
    AccessToken.subject(request.authorization?.replaceFirst('Bearer ', ''));

void main() {
  late InMemoryTokenStore sharedStore;

  setUp(() => sharedStore = InMemoryTokenStore('r-0'));

  /// A tab whose server answers `GET /me` for whoever the token belongs to.
  TestBackend tab() {
    final backend = TestBackend(store: sharedStore);
    backend.adapter.on('GET', ApiPaths.me, (request) {
      final id = userOf(request) ?? _yan;
      return FakeReply.json(
        meJson(id: id, displayName: id == _xena ? 'Xena' : 'Yan'),
      );
    });
    return backend;
  }

  Future<ProviderContainer> signedIn(TestBackend backend) async {
    final container = backend.container()..read(authControllerProvider);
    await container.read(authControllerProvider.notifier).restore();
    expect(container.read(authControllerProvider), isA<Authenticated>());
    return container;
  }

  test("a session ending in one tab keeps the other tab's newer session "
      '(password change)', () async {
    final a = tab();
    final b = tab();
    a.adapter
      ..onJson(
        'POST',
        ApiPaths.refresh,
        tokenPairJson(access: 'a-1', refresh: 'r-1'),
      )
      ..onJson(
        'POST',
        ApiPaths.password,
        tokenPairJson(access: 'a-pw', refresh: 'r-pw'),
      )
      ..onJson('GET', ApiPaths.groups, <Object?>[]);
    b.adapter
      ..onJson(
        'POST',
        ApiPaths.refresh,
        tokenPairJson(access: 'b-1', refresh: 'r-2'),
      )
      // Tab A's password change bumped the token version: B's access token
      // is dead.
      ..onProblem('GET', ApiPaths.groups, 401, ErrorCodes.unauthenticated);
    final tabA = await signedIn(a);
    final tabB = await signedIn(b);
    expect(sharedStore.refreshToken, 'r-2');

    await tabA
        .read(authControllerProvider.notifier)
        .changePassword(currentPassword: 'old password', newPassword: 'x' * 10);
    expect(sharedStore.refreshToken, 'r-pw');

    await expectLater(
      apiCall(tabB.read(groupsClientProvider).listGroups),
      throwsA(isA<ProblemException>()),
    );
    await pumpEventQueue();

    // Tab B is signed out, but A's session (the current device's, per
    // contract section 4.6) survives.
    expect(
      tabB.read(authControllerProvider),
      const Unauthenticated(SignOutReason.sessionExpired),
    );
    expect(b.holder.accessToken, isNull);
    expect(sharedStore.refreshToken, 'r-pw');

    // A's next refresh uses it and stays signed in.
    a.adapter.on('POST', ApiPaths.refresh, (request) {
      final presented = request.jsonMap['refresh_token'];
      return presented == 'r-pw'
          ? FakeReply.json(tokenPairJson(access: 'a-2', refresh: 'r-pw-2'))
          : FakeReply.problem(401, ErrorCodes.refreshInvalid);
    });
    a.clock.advance(const Duration(minutes: 16));
    await apiCall(tabA.read(groupsClientProvider).listGroups);

    expect(tabA.read(authControllerProvider), isA<Authenticated>());
    expect(
      a.adapter.requestsTo('GET', ApiPaths.groups).last.authorization,
      'Bearer a-2',
    );
    expect(sharedStore.refreshToken, 'r-pw-2');
  });

  group('another tab signs in as someone else', () {
    late TestBackend b;
    late ProviderContainer tabB;

    setUp(() async {
      b = tab();
      b.adapter.on('POST', ApiPaths.refresh, (request) {
        final presented = request.jsonMap['refresh_token']! as String;
        final user = presented.startsWith('r-x') ? _xena : _yan;
        return FakeReply.json(
          tokenPairJson(
            access: fakeJwt(sub: user, nonce: presented),
            refresh: '$presented+',
          ),
        );
      });
      tabB = await signedIn(b);
      expect(tabB.read(currentUserIdProvider), _yan);

      // Another tab signs out and in as Xena: the shared store now holds her
      // session. Tab B's access token is about to expire.
      sharedStore.refreshToken = 'r-x-1';
      b.clock.advance(const Duration(minutes: 15));
    });

    test("tab B never sends Yan's request with Xena's token, and switches to "
        'Xena', () async {
      // The profile form, still showing Yan, is saved.
      await expectLater(
        tabB
            .read(authControllerProvider.notifier)
            .updateMe(const MeUpdate(displayName: 'Yan', timezone: 'UTC')),
        throwsA(
          isA<ProblemException>().having(
            (e) => e.code,
            'code',
            ErrorCodes.unauthenticated,
          ),
        ),
      );
      expect(b.adapter.requestsTo('PUT', ApiPaths.me), isEmpty);

      // The tab reloads the user: currentUserId changes, caches reset.
      expect(tabB.read(authControllerProvider), isA<AuthUnknown>());
      await pumpEventQueue(times: 100);
      expect(tabB.read(currentUserIdProvider), _xena);
      expect(tabB.read(currentUserProvider)?.displayName, 'Xena');
      expect(userOf(b.adapter.requestsTo('GET', ApiPaths.me).last), _xena);
    });

    test('data providers that watch currentUserId refetch as the new '
        'account', () async {
      var fetches = 0;
      b.adapter.on('GET', ApiPaths.groups, (_) {
        fetches++;
        return FakeReply.json([groupSummaryJson(name: 'Fetch $fetches')]);
      });
      final groupsProvider = FutureProvider<List<GroupSummary>>((ref) {
        ref.watch(currentUserIdProvider);
        return apiCall(ref.watch(groupsClientProvider).listGroups);
      });
      final subscription = tabB.listen(groupsProvider, (_, _) {});
      addTearDown(subscription.close);

      // Yan's first fetch is refused (Xena's token); the tab switches to
      // Xena and the provider, which watches currentUserId, refetches.
      await pumpEventQueue(times: 100);

      expect(tabB.read(currentUserIdProvider), _xena);
      final groups = await tabB.read(groupsProvider.future);
      expect(groups.single.name, 'Fetch $fetches');
      final sent = b.adapter.requestsTo('GET', ApiPaths.groups);
      expect(sent, isNotEmpty);
      expect(sent.map(userOf), everyElement(_xena));
    });
  });
}
