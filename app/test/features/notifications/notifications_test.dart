import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

const _all = {'polls': true, 'wheel': true, 'reminders': true};

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend()..stubGroups([]));

  Future<void> open(
    WidgetTester tester,
    String location, {
    bool verified = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn(emailVerified: verified)),
        ),
      ],
      location: location,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the profile switches each kind of email', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.notifications, _all)
      ..onJson('PUT', ApiPaths.notifications, {..._all, 'wheel': false});
    await open(tester, Routes.profile);

    expect(find.text('Email notifications'), findsOneWidget);
    await tester.tap(find.text('Wheel results'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('PUT', ApiPaths.notifications).single.jsonMap,
      {..._all, 'wheel': false},
    );
    final wheel = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Wheel results'),
    );
    expect(wheel.value, isFalse);
  });

  testWidgets('an unverified address gets a banner with Send link', (
    tester,
  ) async {
    backend.adapter.onJson(
      'POST',
      ApiPaths.emailVerification,
      null,
      status: 202,
    );
    await open(tester, Routes.groups, verified: false);

    expect(find.text('Confirm your email'), findsOneWidget);
    await tester.tap(find.text('Send link'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('POST', ApiPaths.emailVerification),
      hasLength(1),
    );
    expect(find.text('Check the inbox of ana@example.com.'), findsOneWidget);
    expect(find.text('Resend'), findsOneWidget);
  });

  testWidgets('a verified address gets no banner', (tester) async {
    await open(tester, Routes.groups);

    expect(find.text('Confirm your email'), findsNothing);
  });

  testWidgets('the unsubscribe link turns that kind off', (tester) async {
    backend.adapter.onJson('POST', ApiPaths.unsubscribe, {'kind': 'polls'});
    await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '${Routes.unsubscribe}?token=abc',
    );
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('POST', ApiPaths.unsubscribe).single.query,
      'token=abc',
    );
    expect(find.textContaining("won't get new poll emails"), findsOneWidget);
  });

  testWidgets('a bad unsubscribe link points to the profile', (tester) async {
    backend.adapter.onProblem(
      'POST',
      ApiPaths.unsubscribe,
      422,
      ErrorCodes.invalidToken,
    );
    await tester.pumpFriendsApp(
      overrides: backend.overrides,
      location: '${Routes.unsubscribe}?token=abc',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("doesn't work"), findsOneWidget);
  });

  testWidgets('an invite can be emailed', (tester) async {
    backend
      ..stubGroup(
        group: groupJson(myRole: 'admin'),
        invites: [inviteJson()],
      )
      ..adapter.onJson(
        'POST',
        '${ApiPaths.invite(Ids.groupId, Ids.inviteId)}/email',
        null,
        status: 202,
      );
    await open(tester, Routes.groupHub(Ids.groupId));

    await tester.ensureVisible(find.text('Email').first);
    await tester.tap(find.text('Email').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'bea@example.com',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter
          .requestsTo(
            'POST',
            '${ApiPaths.invite(Ids.groupId, Ids.inviteId)}/email',
          )
          .single
          .jsonMap,
      {'email': 'bea@example.com'},
    );
    expect(find.text('Invite sent'), findsOneWidget);
  });
}
