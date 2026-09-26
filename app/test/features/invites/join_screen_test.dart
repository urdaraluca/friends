import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/auth/presentation/login_screen.dart';
import 'package:friends/features/auth/presentation/register_screen.dart';
import 'package:friends/features/backlog/presentation/backlog_screen.dart';
import 'package:friends/features/invites/presentation/invite_labels.dart';
import 'package:friends/features/invites/presentation/join_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  const code = 'ABCDEFGHJK';
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  void stubPreview(Map<String, Object?> preview) =>
      backend.adapter.onJson('GET', ApiPaths.invitePreview(code), preview);

  Future<ProviderContainer> openJoin(
    WidgetTester tester, {
    required AuthState auth,
    String location = '/join/abcde-fghjk',
  }) => tester.pumpFriendsApp(
    overrides: [
      ...backend.overrides,
      authControllerProvider.overrideWith(() => FakeAuthController(auth)),
    ],
    location: location,
  );

  const signedOut = Unauthenticated(SignOutReason.noSession);

  group('JoinScreen', () {
    testWidgets('previews the group: name, members, who invited, expiry', (
      tester,
    ) async {
      stubPreview(invitePreviewJson(expiresAt: null));

      await openJoin(tester, auth: signedOut);

      // The code in the link is normalized before the preview request.
      expect(backend.adapter.last.path, ApiPaths.invitePreview(code));
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('🎬'), findsOneWidget);
      expect(find.text('3 members'), findsOneWidget);
      expect(find.text('Invited by Bea'), findsOneWidget);
      expect(find.text('Never expires'), findsOneWidget);
      expect(find.text('ABCDE-FGHJK'), findsOneWidget);
    });

    // Every status but `valid`, explained.
    for (final (status, message) in [
      ('expired', 'This invite has expired. Ask for a new one.'),
      (
        'revoked',
        'This invite was revoked, so it no longer works. Ask for a new one.',
      ),
      ('exhausted', 'This invite has been used up. Ask for a new one.'),
      ('something_new', "This invite can't be used. Ask for a new one."),
    ]) {
      testWidgets('explains a $status invite and offers no Join', (
        tester,
      ) async {
        stubPreview(invitePreviewJson(status: status));

        await openJoin(tester, auth: signedIn());

        expect(find.text(message), findsOneWidget);
        expect(find.textContaining('Join'), findsNothing);
        expect(find.text('Go to my groups'), findsOneWidget);
      });
    }

    testWidgets('signed in: Join accepts and opens the group', (tester) async {
      stubPreview(invitePreviewJson());
      backend
        ..stubGroup()
        ..adapter.onJson('POST', ApiPaths.acceptInvite(code), groupJson());
      final container = await openJoin(tester, auth: signedIn());

      await tester.tap(find.text('Join Movie night'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo('POST', ApiPaths.acceptInvite(code)),
        hasLength(1),
      );
      expect(currentLocation(container), '/groups/${Ids.groupId}/backlog');
      expect(find.byType(BacklogScreen), findsOneWidget);
    });

    testWidgets('signed in: a failed Join explains why and reloads the '
        'preview', (tester) async {
      stubPreview(invitePreviewJson());
      backend.adapter.onProblem(
        'POST',
        ApiPaths.acceptInvite(code),
        410,
        ErrorCodes.inviteRevoked,
      );
      await openJoin(tester, auth: signedIn());
      stubPreview(invitePreviewJson(status: 'revoked'));

      await tester.tap(find.text('Join Movie night'));
      await tester.pumpAndSettle();

      expect(
        find.text(inviteUnusableReason(InviteStatus.revoked)!),
        findsOneWidget,
      );
    });

    testWidgets('signed out: Create account carries the code and comes back', (
      tester,
    ) async {
      stubPreview(invitePreviewJson());
      final container = await openJoin(tester, auth: signedOut);

      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(
        currentLocation(container),
        '/register?from=%2Fjoin%2FABCDEFGHJK&invite=ABCDEFGHJK',
      );
      expect(find.byType(RegisterScreen), findsOneWidget);
      final invite = tester.widget<TextField>(
        find.descendant(
          of: find.widgetWithText(TextFormField, 'Invite code'),
          matching: find.byType(TextField),
        ),
      );
      expect(invite.controller!.text, 'ABCDE-FGHJK');
    });

    testWidgets('signed out: Log in comes back here', (tester) async {
      stubPreview(invitePreviewJson());
      final container = await openJoin(tester, auth: signedOut);

      await tester.tap(find.text('Log in'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/login?from=%2Fjoin%2FABCDEFGHJK');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('an unknown code says so', (tester) async {
      await openJoin(tester, auth: signedOut);

      expect(find.text("We couldn't find this invite."), findsOneWidget);
    });

    testWidgets("a malformed code isn't looked up", (tester) async {
      await openJoin(tester, auth: signedOut, location: '/join/nope');

      expect(find.text("This invite link doesn't look right."), findsOneWidget);
      expect(backend.adapter.requests, isEmpty);
      expect(find.byType(JoinScreen), findsOneWidget);
    });
  });
}
