import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/push/web_push.dart';
import 'package:friends/core/router/routes.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

const _all = {
  'polls': true,
  'wheel': true,
  'reminders': true,
  'members': true,
  'plans': true,
  'email': false,
};

const _sub = BrowserPushSubscription(
  endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
  p256dh: 'key',
  auth: 'secret',
);

/// A browser that can do push; [grant] decides the permission prompt.
class FakeWebPush implements WebPush {
  new({this.permission = PushPermission.prompt, this.grant = true});

  @override
  PushPermission permission;

  final bool grant;
  BrowserPushSubscription? subscription;

  @override
  bool get supported => true;

  @override
  Future<BrowserPushSubscription?> current() async => subscription;

  @override
  Future<BrowserPushSubscription?> subscribe(String vapidPublicKey) async {
    permission = grant ? PushPermission.granted : PushPermission.denied;
    return subscription = grant ? _sub : null;
  }

  @override
  Future<String?> unsubscribe() async {
    final endpoint = subscription?.endpoint;
    subscription = null;
    return endpoint;
  }
}

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend()..stubGroups([]));

  Future<void> open(
    WidgetTester tester,
    String location, {
    bool verified = true,
    WebPush? push,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        if (push != null) webPushProvider.overrideWithValue(push),
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn(emailVerified: verified)),
        ),
      ],
      location: location,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the profile switches each kind of notification', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.notifications, _all)
      ..onJson('PUT', ApiPaths.notifications, {..._all, 'wheel': false});
    await open(tester, Routes.profile);

    expect(find.text('Notifications'), findsWidgets);
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

  testWidgets('email on with an unverified address shows Send link', (
    tester,
  ) async {
    backend.adapter
      ..onJson('GET', ApiPaths.notifications, {..._all, 'email': true})
      ..onJson('POST', ApiPaths.emailVerification, null, status: 202);
    await open(tester, Routes.profile, verified: false);

    expect(find.text('Confirm your email'), findsWidgets);
    await tester.tap(find.text('Send link').first);
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('POST', ApiPaths.emailVerification),
      hasLength(1),
    );
    expect(find.text('Check the inbox of ana@example.com.'), findsOneWidget);
    expect(find.text('Resend'), findsOneWidget);
  });

  testWidgets('a verified address gets no banner', (tester) async {
    backend.adapter.onJson('GET', ApiPaths.notifications, {
      ..._all,
      'email': true,
    });
    await open(tester, Routes.profile);

    expect(find.text('Confirm your email'), findsNothing);
  });

  group('push', () {
    void stubPush() => backend.adapter
      ..onJson('GET', ApiPaths.notifications, _all)
      ..onJson('GET', ApiPaths.pushConfig, {'public_key': 'vapid'})
      ..onJson('PUT', ApiPaths.pushSubscription, null, status: 204)
      ..onJson('DELETE', ApiPaths.pushSubscription, null, status: 204);

    testWidgets('the groups prompt turns push on', (tester) async {
      stubPush();
      final push = FakeWebPush();
      await open(tester, Routes.groups, push: push);

      expect(find.text('Get notified'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('PUT', ApiPaths.pushSubscription)
            .single
            .jsonMap,
        {
          'endpoint': _sub.endpoint,
          'keys': {'p256dh': 'key', 'auth': 'secret'},
        },
      );
      expect(find.text('Push notifications are on'), findsOneWidget);
      expect(find.text('Get notified'), findsNothing);
    });

    testWidgets('refused permission says notifications are blocked', (
      tester,
    ) async {
      stubPush();
      await open(tester, Routes.groups, push: FakeWebPush(grant: false));

      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo('PUT', ApiPaths.pushSubscription),
        isEmpty,
      );
      expect(find.textContaining('blocked for this site'), findsOneWidget);
      expect(find.text('Get notified'), findsNothing);
    });

    testWidgets('no prompt without a server key', (tester) async {
      stubPush();
      backend.adapter.onJson('GET', ApiPaths.pushConfig, {'public_key': null});
      await open(tester, Routes.groups, push: FakeWebPush());

      expect(find.text('Get notified'), findsNothing);
    });

    testWidgets('the profile switch turns push off', (tester) async {
      stubPush();
      final push = FakeWebPush(permission: PushPermission.granted)
        ..subscription = _sub;
      await open(tester, Routes.profile, push: push);

      final tile = find.widgetWithText(
        SwitchListTile,
        'Push notifications on this device',
      );
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(
        backend.adapter
            .requestsTo('DELETE', ApiPaths.pushSubscription)
            .single
            .query,
        'endpoint=${Uri.encodeQueryComponent(_sub.endpoint)}',
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(push.subscription, isNull);
    });
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
    expect(
      find.textContaining("won't get new poll notifications"),
      findsOneWidget,
    );
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
