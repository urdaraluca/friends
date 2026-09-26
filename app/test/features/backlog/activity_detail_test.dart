import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/links/open_link.dart';
import 'package:friends/core/router/routes.dart';
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

void main() {
  late TestBackend backend;
  late _RecordingLinkOpener links;

  setUp(() {
    backend = TestBackend()
      ..stubGroup()
      ..stubBacklog(categories: categoryTreeJson());
    links = _RecordingLinkOpener();
  });

  Future<ProviderContainer> openDetail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    return await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        linkOpenerProvider.overrideWithValue(links),
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.activity(Ids.groupId, Ids.activityId),
    );
  }

  testWidgets('shows the custom fields by type and opens links', (
    tester,
  ) async {
    backend.adapter.onJson(
      'GET',
      ApiPaths.activity(Ids.activityId),
      activityJson(
        description: 'Sand and worms.',
        attributes: {
          'genre': 'Drama',
          'imdb_rating': 8.1,
          'imdb_url': 'https://www.imdb.com/title/tt1160419/',
          'year': 2021,
        },
        links: [
          {'url': 'https://example.com/tickets', 'label': 'Tickets'},
        ],
      ),
    );

    await openDetail(tester);

    expect(find.text('Sand and worms.'), findsOneWidget);
    expect(find.text('8.1 / 10'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Drama'), findsOneWidget);
    expect(find.text('2021'), findsOneWidget);
    expect(find.text('Not in the calendar yet.'), findsOneWidget);

    await tester.tap(find.text('www.imdb.com/title/tt1160419/'));
    await tester.tap(find.text('Tickets'));
    await tester.pumpAndSettle();
    expect(links.opened.map((u) => u.toString()), [
      'https://www.imdb.com/title/tt1160419/',
      'https://example.com/tickets',
    ]);
  });

  testWidgets('claiming an unowned idea sends a PUT with my ID and version', (
    tester,
  ) async {
    backend.adapter
      ..onJson(
        'GET',
        ApiPaths.activity(Ids.activityId),
        activityJson(version: 3),
      )
      ..onJson(
        'PUT',
        ApiPaths.activity(Ids.activityId),
        activityJson(version: 4, owner: userPublicJson()),
      );
    await openDetail(tester);

    expect(find.text('Nobody is on it yet'), findsOneWidget);
    await tester.tap(find.text("I'll do it"));
    await tester.pumpAndSettle();

    final body = backend.adapter
        .requestsTo('PUT', ApiPaths.activity(Ids.activityId))
        .single
        .jsonMap;
    expect(body['owner_id'], Ids.anaId);
    expect(body['version'], 3);
    expect(body['title'], 'Dune');
  });

  testWidgets("a member can't hand someone else's idea over", (tester) async {
    backend.adapter.onJson(
      'GET',
      ApiPaths.activity(Ids.activityId),
      activityJson(
        owner: userPublicJson(id: Ids.beaId, displayName: 'Bea'),
      ),
    );
    await openDetail(tester);

    expect(find.text('Bea is on it'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    expect(find.text("I'll do it"), findsNothing);
  });

  testWidgets('the status menu posts the new status', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.activity(Ids.activityId), activityJson())
      ..onJson(
        'POST',
        ApiPaths.activityStatus(Ids.activityId),
        activityJson(status: 'planning'),
      );
    await openDetail(tester);

    await tester.tap(find.byTooltip('Change status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Planning').last);
    await tester.pumpAndSettle();

    expect(
      backend.adapter
          .requestsTo('POST', ApiPaths.activityStatus(Ids.activityId))
          .single
          .jsonMap,
      {'status': 'planning'},
    );
  });

  testWidgets('delete asks first and goes back to the backlog', (tester) async {
    backend.adapter
      ..onJson('GET', ApiPaths.activity(Ids.activityId), activityJson())
      ..onJson('DELETE', ApiPaths.activity(Ids.activityId), null, status: 204);
    final container = await openDetail(tester);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "Dune"?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('DELETE', ApiPaths.activity(Ids.activityId)),
      hasLength(1),
    );
    expect(currentLocation(container), Routes.groupBacklog(Ids.groupId));
  });
}
