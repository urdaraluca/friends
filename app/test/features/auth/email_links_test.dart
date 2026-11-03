import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/auth/presentation/forgot_password_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('"Forgot password?" asks for a link without saying more', (
    tester,
  ) async {
    backend.adapter.onJson(
      'POST',
      ApiPaths.passwordResetRequest,
      null,
      status: 202,
    );
    await tester.pumpFriendsApp(overrides: backend.overrides);

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    await tester.enterText(field('Email'), ' ana@example.com ');
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter
          .requestsTo('POST', ApiPaths.passwordResetRequest)
          .single
          .jsonMap,
      {'email': 'ana@example.com'},
    );
    expect(find.textContaining('a link is on its way'), findsOneWidget);
  });

  testWidgets('the reset link sets a new password, then sign in', (
    tester,
  ) async {
    backend.adapter.onJson('POST', ApiPaths.passwordReset, null, status: 204);
    final container = await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '${Routes.resetPassword}?token=abc%2Bdef',
    );

    await tester.enterText(field('New password'), 'a brand new secret');
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('POST', ApiPaths.passwordReset).single.jsonMap,
      {'token': 'abc+def', 'new_password': 'a brand new secret'},
    );
    expect(find.textContaining('Your password is changed'), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(currentLocation(container), Routes.login);
  });

  testWidgets('a used or expired reset link offers a new one', (tester) async {
    backend.adapter.onProblem(
      'POST',
      ApiPaths.passwordReset,
      422,
      ErrorCodes.invalidToken,
      errors: [
        {'field': 'token', 'message': 'expired', 'type': 'invalid_token'},
      ],
    );
    await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '${Routes.resetPassword}?token=old',
    );

    await tester.enterText(field('New password'), 'a brand new secret');
    await tester.tap(find.text('Set password'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already used or expired'), findsOneWidget);
    expect(find.text('Ask for a new link'), findsOneWidget);
  });

  testWidgets('the verification link confirms the address, signed out', (
    tester,
  ) async {
    backend.adapter.onJson('POST', ApiPaths.verifyEmail, null, status: 204);
    await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '${Routes.verifyEmail}?token=tok',
    );
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('POST', ApiPaths.verifyEmail).single.jsonMap,
      {'token': 'tok'},
    );
    expect(
      find.text('Your email address is confirmed. Thanks!'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('signed in, verifying reloads me and hides the banner', (
    tester,
  ) async {
    backend
      ..stubGroups([])
      ..adapter.onJson('POST', ApiPaths.verifyEmail, null, status: 204)
      ..adapter.onJson('GET', ApiPaths.me, meJson());
    final container = await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn(emailVerified: false)),
        ),
      ],
      location: '${Routes.verifyEmail}?token=tok',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(currentLocation(container), Routes.groups);
    expect(find.text('Confirm your email'), findsNothing);
  });

  testWidgets('a bad verification link says so', (tester) async {
    backend.adapter.onProblem(
      'POST',
      ApiPaths.verifyEmail,
      422,
      ErrorCodes.invalidToken,
    );
    await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '${Routes.verifyEmail}?token=tok',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('invalid or has expired'), findsOneWidget);
  });
}
