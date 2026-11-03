import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/calendar/presentation/calendar_feed_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

class _RecordingLinkOpener extends LinkOpener {
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }
}

const _url = 'https://friends.example/api/v1/calendar-feed/s3cret.ics';
const Map<String, String> _on = {
  'url': _url,
  'webcal_url': 'webcal://friends.example/api/v1/calendar-feed/s3cret.ics',
};
const Map<String, String?> _off = {'url': null, 'webcal_url': null};

void main() {
  late TestBackend backend;
  late _RecordingLinkOpener links;

  setUp(() {
    backend = TestBackend()..stubGroup();
    links = _RecordingLinkOpener();
  });

  Future<void> open(
    WidgetTester tester, {
    String location = Routes.calendarFeed,
  }) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        linkOpenerProvider.overrideWithValue(links),
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: location,
    );
  }

  testWidgets('off: turning it on shows the link', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.calendarFeed, _off)
      ..onJson('POST', ApiPaths.calendarFeed, _on);
    await open(tester);

    expect(find.text(_url), findsNothing);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('POST', ApiPaths.calendarFeed),
      hasLength(1),
    );
    expect(find.text(_url), findsOneWidget);
  });

  testWidgets('on: opens the webcal link and copies the https one', (
    tester,
  ) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text'] as String?,
          );
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    backend.adapter.onJson('GET', ApiPaths.calendarFeed, _on);
    await open(tester);

    await tester.tap(find.text('Add to my calendar app'));
    await tester.pumpAndSettle();
    expect(links.opened, [Uri.parse(_on['webcal_url']!)]);

    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, [_url]);
    expect(find.text('Link copied'), findsOneWidget);
  });

  testWidgets('turning it off asks first', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.calendarFeed, _on)
      ..onJson('DELETE', ApiPaths.calendarFeed, null, status: 204);
    await open(tester);

    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.text('Turn off the subscription?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Turn off'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('DELETE', ApiPaths.calendarFeed),
      hasLength(1),
    );
    expect(find.text(_url), findsNothing);
    expect(find.text('Turn on'), findsOneWidget);
    expect(find.text('Subscription turned off'), findsOneWidget);
  });

  testWidgets('my calendar links to it', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.myCalendar, calendarJson([]))
      ..onJson('GET', ApiPaths.calendarFeed, _off);
    await open(tester, location: Routes.myCalendar);

    await tester.tap(find.byTooltip('Subscribe from another calendar'));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarFeedScreen), findsOneWidget);
  });
}
