import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/presentation/backlog_screen.dart';
import 'package:friends/features/backlog/presentation/widgets/activity_card.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend()..stubGroup());

  Future<ProviderContainer> openBacklog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    return await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.groupBacklog(Ids.groupId),
    );
  }

  Future<void> tapChip(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(FilterChip, label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
  }

  List<RecordedRequest> listRequests() =>
      backend.adapter.requestsTo('GET', ApiPaths.activities(Ids.groupId));

  testWidgets('shows cards with category, status, cost and card attributes', (
    tester,
  ) async {
    backend.stubBacklog(
      activities: [
        activitySummaryJson(
          estimatedCost: 12,
          cardAttributes: [
            {
              'key': 'imdb_rating',
              'label': 'IMDb rating',
              'type': 'rating',
              'value': 8.1,
            },
          ],
        ),
        activitySummaryJson(
          id: Ids.otherActivityId,
          title: 'Catan',
          categoryId: Ids.gamesCategoryId,
          status: 'planning',
          myUnvotedPollCount: 1,
        ),
      ],
    );

    await openBacklog(tester);

    expect(find.byType(BacklogScreen), findsOneWidget);
    expect(find.byType(ActivityCard), findsNWidgets(2));
    expect(find.text('Dune'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ActivityCard),
        matching: find.text('Movie night'),
      ),
      findsOneWidget,
    );
    expect(find.text('⭐ 8.1'), findsOneWidget);
    expect(find.text('~12 EUR pp'), findsOneWidget);
    expect(find.text('Planning'), findsWidgets);
    // The "Vote" badge only on the activity with an unanswered poll.
    expect(find.byType(VoteBadge), findsOneWidget);
    expect(listRequests().single.queryParametersAll['status'], [
      'idea',
      'planning',
      'scheduled',
    ]);
  });

  testWidgets('filter chips change the query', (tester) async {
    await openBacklog(tester);

    await tapChip(tester, 'Idea');
    await tester.pumpAndSettle();
    expect(
      listRequests().last.query,
      contains('status=planning&status=scheduled'),
    );
    expect(listRequests().last.queryParametersAll['status'], [
      'planning',
      'scheduled',
    ]);

    await tapChip(tester, 'Show archived');
    await tester.pumpAndSettle();
    expect(listRequests().last.queryParametersAll['status'], [
      'planning',
      'scheduled',
      'done',
      'dropped',
    ]);

    await tapChip(tester, "I'm interested");
    await tester.pumpAndSettle();
    await tapChip(tester, 'Mine');
    await tester.pumpAndSettle();
    final query = listRequests().last.queryParametersAll;
    expect(query['interested_by'], [Ids.anaId]);
    expect(query['owner_id'], [Ids.anaId]);
  });

  testWidgets('the search is debounced and sends q', (tester) async {
    await openBacklog(tester);
    final before = listRequests().length;

    await tester.enterText(find.byType(TextField).first, 'du');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField).first, 'dune');
    await tester.pump(const Duration(milliseconds: 100));
    expect(listRequests(), hasLength(before)); // still typing
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(listRequests(), hasLength(before + 1));
    expect(listRequests().last.queryParametersAll['q'], ['dune']);
  });

  testWidgets('the pager appends pages and stops at next_cursor == null', (
    tester,
  ) async {
    backend.adapter.on('GET', ApiPaths.activities(Ids.groupId), (request) {
      final cursor = request.queryParametersAll['cursor']?.single;
      return switch (cursor) {
        null => FakeReply.json(
          activityPageJson([
            for (var i = 0; i < 3; i++)
              activitySummaryJson(id: 'a$i', title: 'Page 1 #$i'),
          ], nextCursor: 'c2'),
        ),
        'c2' => FakeReply.json(
          activityPageJson([activitySummaryJson(id: 'b0', title: 'Page 2 #0')]),
        ),
        _ => throw StateError('unexpected cursor $cursor'),
      };
    });

    await openBacklog(tester);

    expect(find.byType(ActivityCard), findsNWidgets(4));
    expect(find.text('Page 2 #0'), findsOneWidget);
    expect(listRequests().map((r) => r.queryParametersAll['cursor']), [
      null,
      ['c2'],
    ]);
  });

  testWidgets('the interest heart updates at once and rolls back on error', (
    tester,
  ) async {
    backend
      ..stubBacklog(
        activities: [
          activitySummaryJson(interestCount: 3, iAmInterested: false),
        ],
      )
      ..adapter.on('PUT', ApiPaths.interest(Ids.activityId), (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const FakeReply.networkError();
      });
    await openBacklog(tester);
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byType(InterestButton));
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.textContaining("Can't reach the server"), findsOneWidget);
  });

  testWidgets('an empty backlog invites adding the first idea', (tester) async {
    await openBacklog(tester);

    expect(find.text('No ideas yet'), findsOneWidget);
    await tester.tap(find.text('Add the first idea'));
    await tester.pumpAndSettle();
    expect(find.text('New idea'), findsWidgets);
  });
}
