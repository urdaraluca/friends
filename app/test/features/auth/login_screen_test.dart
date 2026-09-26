import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/auth/presentation/login_screen.dart';
import 'package:friends/features/profile/presentation/profile_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String email = 'ana@example.com',
    String password = 'correct horse battery',
  }) async {
    await tester.enterText(field('Email'), email);
    await tester.enterText(field('Password'), password);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }

  int loginCalls() => backend.adapter.requestsTo('POST', ApiPaths.login).length;

  group('LoginScreen', () {
    testWidgets('validates the fields before sending anything', (tester) async {
      await tester.pumpFriendsApp(overrides: backend.overrides);
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);

      await tester.enterText(field('Email'), 'not-an-email');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(loginCalls(), 0);
    });

    testWidgets('shows server field errors on their fields', (tester) async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.login,
        422,
        ErrorCodes.validationError,
        errors: [
          {
            'field': 'email',
            'message': 'The email address is not valid.',
            'type': 'value_error',
          },
        ],
      );
      await tester.pumpFriendsApp(overrides: backend.overrides);

      await fillAndSubmit(tester, email: 'ana@example.c');

      final emailField = tester.widget<TextField>(
        find.descendant(of: field('Email'), matching: find.byType(TextField)),
      );
      expect(
        emailField.decoration?.errorText,
        'The email address is not valid.',
      );
      expect(find.text('The email address is not valid.'), findsOneWidget);

      // Editing the field clears its server error.
      await tester.enterText(field('Email'), 'ana@example.com');
      await tester.pumpAndSettle();
      expect(find.text('The email address is not valid.'), findsNothing);
    });

    testWidgets('shows wrong credentials in a banner', (tester) async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.login,
        401,
        ErrorCodes.invalidCredentials,
      );
      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
      );

      await fillAndSubmit(tester);

      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        container.read(authControllerProvider),
        const Unauthenticated(SignOutReason.noSession),
      );
      expect(backend.refreshCount, 0);
    });

    testWidgets('shows network errors in a banner', (tester) async {
      backend.adapter.on(
        'POST',
        ApiPaths.login,
        (_) => const FakeReply.networkError(),
      );
      await tester.pumpFriendsApp(overrides: backend.overrides);

      await fillAndSubmit(tester);

      expect(
        find.text(
          "Can't reach the server. Check your connection and try again.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('signs in and returns to from', (tester) async {
      backend.adapter.onJson('POST', ApiPaths.login, authSessionJson());
      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/profile',
      );
      expect(currentLocation(container), '/login?from=%2Fprofile');

      await fillAndSubmit(tester);

      expect(currentLocation(container), '/profile');
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(
        backend.adapter.requestsTo('POST', ApiPaths.login).single.jsonMap,
        {
          'email': 'ana@example.com',
          'password': 'correct horse battery',
          'device_label': 'web',
        },
      );
      expect(backend.store.refreshToken, 'refresh-1');
    });

    testWidgets('links to the register screen', (tester) async {
      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/profile',
      );

      await tester.tap(find.text('New here? Create an account'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/register?from=%2Fprofile');
    });
  });
}
