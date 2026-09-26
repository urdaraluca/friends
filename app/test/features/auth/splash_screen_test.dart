import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/auth/presentation/splash_screen.dart';
import 'package:friends/features/groups/presentation/groups_list_screen.dart';
import 'package:friends/features/profile/presentation/profile_screen.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  group('SplashScreen', () {
    testWidgets('restores a stored session and moves on to from', (
      tester,
    ) async {
      final backend = TestBackend(storedRefreshToken: 'refresh-0')
        ..stubRestore();

      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/profile',
      );

      expect(currentLocation(container), '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(backend.refreshCount, 1);
    });

    testWidgets("offers Retry when the server can't be reached, and keeps "
        'the session', (tester) async {
      final backend = TestBackend(storedRefreshToken: 'refresh-0');
      backend.adapter.on(
        'POST',
        ApiPaths.refresh,
        (_) => const FakeReply.networkError(),
      );

      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
      );

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text("Can't reach the server"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Server status'), findsOneWidget);
      expect(container.read(authControllerProvider), isA<AuthUnknown>());
      expect(backend.store.refreshToken, 'refresh-0');

      // The server is back.
      backend.stubRestore();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/groups');
      expect(find.byType(GroupsListScreen), findsOneWidget);
      expect(find.text('No groups yet'), findsOneWidget);
    });

    testWidgets('shows a spinner while restoring', (tester) async {
      final backend = TestBackend(storedRefreshToken: 'refresh-0');
      backend.adapter.on('POST', ApiPaths.refresh, (_) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return FakeReply.json(tokenPairJson());
      });
      backend.adapter
        ..onJson('GET', ApiPaths.me, meJson())
        ..onJson('GET', ApiPaths.groups, <Object?>[]);

      await tester.pumpFriendsApp(overrides: backend.overrides, settle: false);

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(GroupsListScreen), findsOneWidget);
    });
  });
}
