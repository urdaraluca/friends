import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/auth/presentation/register_screen.dart';
import 'package:friends/features/backlog/presentation/backlog_screen.dart';
import 'package:friends/features/groups/presentation/group_shell.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(
        find.descendant(of: field(label), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String displayName = 'Ana',
    String email = 'ana@example.com',
    String password = 'long enough password',
    String? inviteCode,
  }) async {
    await tester.enterText(field('Display name'), displayName);
    await tester.enterText(field('Email'), email);
    await tester.enterText(field('Password'), password);
    if (inviteCode != null) {
      await tester.enterText(field('Invite code'), inviteCode);
    }
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
  }

  List<Map<String, Object?>> registerBodies() => [
    for (final request in backend.adapter.requestsTo('POST', ApiPaths.register))
      request.jsonMap,
  ];

  group('RegisterScreen', () {
    testWidgets('shows the invite-only message on 403 registration_closed', (
      tester,
    ) async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.register,
        403,
        ErrorCodes.registrationClosed,
      );
      await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/register',
      );

      await fillAndSubmit(tester);

      expect(
        find.text('Friends is invite-only — ask a friend for an invite link'),
        findsOneWidget,
      );
      expect(find.byType(RegisterScreen), findsOneWidget);
      expect(registerBodies().single['invite_code'], isNull);
    });

    testWidgets('validates the fields before sending anything', (tester) async {
      await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/register',
      );

      await fillAndSubmit(
        tester,
        displayName: '  ',
        password: 'short',
        inviteCode: 'not a code',
      );

      expect(find.text('Enter a display name.'), findsOneWidget);
      expect(find.text('Use at least 10 characters.'), findsOneWidget);
      expect(
        find.text("That doesn't look like an invite code."),
        findsOneWidget,
      );
      expect(registerBodies(), isEmpty);
    });

    testWidgets('normalizes the invite code, accepts a pasted link, and '
        'opens the group the invite joined', (tester) async {
      backend
        ..adapter.onJson(
          'POST',
          ApiPaths.register,
          authSessionJson(joinedGroup: groupSummaryJson()),
          status: 201,
        )
        ..stubGroup();
      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/register',
      );

      await fillAndSubmit(
        tester,
        inviteCode: 'https://friends.example.com/join/abcd-efgh-ik',
      );

      expect(registerBodies().single, {
        'email': 'ana@example.com',
        'password': 'long enough password',
        'display_name': 'Ana',
        'timezone': 'Europe/Bucharest',
        'device_label': 'web',
        'invite_code': 'ABCDEFGH1K',
      });
      expect(currentLocation(container), '/groups/${Ids.groupId}/backlog');
      expect(find.byType(BacklogScreen), findsOneWidget);
      expect(find.byType(GroupShell), findsOneWidget);
    });

    testWidgets('without a joined group, goes back to from', (tester) async {
      backend.adapter.onJson(
        'POST',
        ApiPaths.register,
        authSessionJson(),
        status: 201,
      );
      backend.adapter.onJson(
        'GET',
        ApiPaths.invitePreview('ABCDEFGHJK'),
        invitePreviewJson(),
      );
      final container = await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: Routes.registerWith(from: Routes.join('ABCDEFGHJK')),
      );

      // The code comes from `from`, and is pre-filled.
      expect(fieldText(tester, 'Invite code'), 'ABCDE-FGHJK');
      await tester.enterText(field('Invite code'), '');
      await fillAndSubmit(tester);

      expect(registerBodies().single['invite_code'], isNull);
      expect(currentLocation(container), '/join/ABCDEFGHJK');
    });

    testWidgets('pre-fills the invite code from the link', (tester) async {
      await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/register?invite=abcdefghjk',
      );

      expect(fieldText(tester, 'Invite code'), 'ABCDE-FGHJK');
    });

    testWidgets('puts invite and email errors on their fields', (tester) async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.register,
        404,
        ErrorCodes.notFound,
      );
      await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/register',
      );

      await fillAndSubmit(tester, inviteCode: 'ABCDE-FGHJK');
      expect(find.text("We couldn't find this invite code."), findsOneWidget);

      backend.adapter.onProblem(
        'POST',
        ApiPaths.register,
        409,
        ErrorCodes.emailTaken,
      );
      // A field with a server error blocks resubmitting until it is edited.
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(registerBodies(), hasLength(1));

      await tester.enterText(field('Invite code'), 'ABCDE-FGHJM');
      await tester.pumpAndSettle();
      expect(find.text("We couldn't find this invite code."), findsNothing);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      expect(registerBodies(), hasLength(2));
      expect(registerBodies().last['invite_code'], 'ABCDEFGHJM');
      expect(
        find.text('An account with this email already exists.'),
        findsOneWidget,
      );
    });

    testWidgets('an expired invite is explained on the invite field', (
      tester,
    ) async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.register,
        410,
        ErrorCodes.inviteExpired,
      );
      await tester.pumpFriendsApp(
        overrides: backend.overrides,
        location: '/register',
      );

      await fillAndSubmit(tester, inviteCode: 'ABCDE-FGHJK');

      expect(find.text('This invite has expired.'), findsOneWidget);
    });
  });
}
