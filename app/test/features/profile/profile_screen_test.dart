import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/auth/presentation/login_screen.dart';
import 'package:friends/features/home/presentation/home_screen.dart';
import 'package:friends/features/profile/presentation/profile_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  /// Signs in by restoring a stored session, then opens `/profile` on a
  /// screen tall enough to show every section.
  Future<ProviderContainer> openProfile(
    WidgetTester tester, {
    Map<String, Object?>? me,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend = TestBackend(storedRefreshToken: 'refresh-0')..stubRestore(me: me);
    final container = await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '/profile',
    );
    expect(find.byType(ProfileScreen), findsOneWidget);
    return container;
  }

  group('ProfileScreen', () {
    testWidgets('saves the profile with PUT /me', (tester) async {
      await openProfile(tester);
      backend.adapter.onJson(
        'PUT',
        ApiPaths.me,
        meJson(displayName: 'Ana Maria'),
      );

      await tester.enterText(field('Display name'), ' Ana Maria ');
      await tester.enterText(field('Year'), '1990');
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      // Month and day are required together with a year.
      expect(find.text('Pick a month and a day for the year.'), findsOneWidget);
      expect(backend.adapter.requestsTo('PUT', ApiPaths.me), isEmpty);

      await tester.enterText(field('Year'), '');
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      expect(backend.adapter.requestsTo('PUT', ApiPaths.me).single.jsonMap, {
        'display_name': 'Ana Maria',
        'birthday': null,
        'timezone': 'Europe/Bucharest',
        'locale': null,
        'avatar_url': null,
      });
      expect(find.text('Profile saved'), findsOneWidget);
    });

    testWidgets('29 February needs a leap year only when a year is given', (
      tester,
    ) async {
      await openProfile(
        tester,
        me: meJson(birthday: {'month': 2, 'day': 29, 'year': null}),
      );
      backend.adapter.onJson('PUT', ApiPaths.me, meJson());

      // The day picker keeps 29 while a non-leap year is typed.
      await tester.enterText(field('Year'), '2023');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      expect(find.text('That day does not exist in 2023.'), findsOneWidget);
      expect(backend.adapter.requestsTo('PUT', ApiPaths.me), isEmpty);

      await tester.enterText(field('Year'), '2024');
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('PUT', ApiPaths.me)
            .single
            .jsonMap['birthday'],
        {'month': 2, 'day': 29, 'year': 2024},
      );
    });

    testWidgets('offers the device timezone when it differs', (tester) async {
      await openProfile(tester, me: meJson(timezone: 'UTC'));
      backend.adapter.onJson('PUT', ApiPaths.me, meJson());

      final useDevice = find.text('Use device timezone (Europe/Bucharest)');
      expect(useDevice, findsOneWidget);

      await tester.tap(useDevice);
      await tester.pumpAndSettle();
      expect(useDevice, findsNothing);

      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('PUT', ApiPaths.me)
            .single
            .jsonMap['timezone'],
        'Europe/Bucharest',
      );
    });

    testWidgets('shows server errors on the profile fields', (tester) async {
      await openProfile(tester);
      backend.adapter.onProblem(
        'PUT',
        ApiPaths.me,
        422,
        ErrorCodes.validationError,
        errors: [
          {
            'field': 'timezone',
            'message': 'Unknown timezone.',
            'type': 'value_error',
          },
        ],
      );

      await tester.enterText(field('Timezone'), 'Mars/Olympus');
      await tester.tap(find.text('Save profile'));
      await tester.pumpAndSettle();

      expect(find.text('Unknown timezone.'), findsOneWidget);
    });

    testWidgets('a wrong current password shows on current_password', (
      tester,
    ) async {
      await openProfile(tester);
      backend.adapter.onProblem(
        'POST',
        ApiPaths.password,
        422,
        ErrorCodes.wrongPassword,
        errors: [
          {
            'field': 'current_password',
            'message': 'The current password is wrong.',
            'type': 'wrong_password',
          },
        ],
      );

      await tester.enterText(field('Current password'), 'not my password');
      await tester.enterText(field('New password'), 'a brand new password');
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();

      final current = tester.widget<TextField>(
        find.descendant(
          of: field('Current password'),
          matching: find.byType(TextField),
        ),
      );
      expect(current.decoration?.errorText, 'The current password is wrong.');
      // Still signed in: a 422, not a 401.
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(backend.store.refreshToken, 'refresh-1');
    });

    testWidgets('changing the password stores the returned tokens', (
      tester,
    ) async {
      await openProfile(tester);
      backend.adapter.onJson(
        'POST',
        ApiPaths.password,
        tokenPairJson(access: 'access-pw', refresh: 'refresh-pw'),
      );

      await tester.enterText(field('Current password'), 'my old password');
      await tester.enterText(field('New password'), 'a brand new password');
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();

      expect(
        find.text('Password changed. Your other devices have been signed out.'),
        findsOneWidget,
      );
      expect(backend.store.refreshToken, 'refresh-pw');
      expect(backend.holder.accessToken, 'access-pw');
    });

    testWidgets('opened directly, it offers a way home', (tester) async {
      final container = await openProfile(tester);

      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/');
      expect(find.byType(HomeScreen), findsOneWidget);

      // Pushed from home, it has a back button instead.
      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Home'), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('logs out', (tester) async {
      final container = await openProfile(tester);
      backend.adapter.on(
        'POST',
        ApiPaths.logout,
        (_) => const FakeReply.noContent(),
      );

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        container.read(authControllerProvider),
        const Unauthenticated(SignOutReason.signedOut),
      );
      expect(backend.store.refreshToken, isNull);
    });

    testWidgets('logs out everywhere after a confirmation', (tester) async {
      await openProfile(tester);
      backend.adapter.on(
        'POST',
        ApiPaths.logoutAll,
        (_) => const FakeReply.noContent(),
      );

      await tester.tap(find.text('Log out everywhere'));
      await tester.pumpAndSettle();
      expect(find.text('Log out everywhere?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log out everywhere'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo('POST', ApiPaths.logoutAll),
        hasLength(1),
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('deletes the account after a password confirmation', (
      tester,
    ) async {
      await openProfile(tester);
      backend.adapter.on(
        'POST',
        ApiPaths.deletion,
        (request) => request.jsonMap['password'] == 'my password'
            ? const FakeReply.noContent()
            : FakeReply.problem(422, ErrorCodes.wrongPassword),
      );

      await tester.tap(find.text('Delete my account'));
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);

      final confirm = find.widgetWithText(FilledButton, 'Delete account');
      final password = find.descendant(
        of: find.byType(AlertDialog),
        matching: field('Password'),
      );
      await tester.enterText(password, 'wrong');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Wrong password.'), findsOneWidget);

      await tester.enterText(password, 'my password');
      // Let the dialog shrink as the error goes away before tapping.
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
      expect(backend.store.refreshToken, isNull);
    });
  });
}
