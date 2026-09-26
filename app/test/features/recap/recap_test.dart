import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/app_router.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/recap/domain/recap_period.dart';
import 'package:friends/features/recap/domain/recap_story.dart';
import 'package:friends/features/recap/presentation/recap_screen.dart';
import 'package:friends/features/recap/presentation/widgets/recap_banner.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

Recap _recap({
  String period = 'month',
  bool complete = true,
  List<Map<String, Object?>>? memories,
  Map<String, Object?>? busiestMonth,
  int ideasAdded = 5,
  int eventsPlanned = 2,
  int pollsCreated = 1,
  int wheelDecisions = 3,
}) => Recap.fromJson(
  recapJson(
    period: period,
    start: period == 'year' ? '2026-01-01' : '2026-10-01',
    complete: complete,
    memories: memories,
    busiestMonth: busiestMonth,
    ideasAdded: ideasAdded,
    eventsPlanned: eventsPlanned,
    pollsCreated: pollsCreated,
    wheelDecisions: wheelDecisions,
  ),
);

void main() {
  group('periods and the banner', () {
    test('labels and shifts', () {
      expect(
        periodLabel(RecapPeriod.month, DateTime(2026, 10)),
        'October 2026',
      );
      expect(periodLabel(RecapPeriod.year, DateTime(2026)), '2026');
      expect(
        shiftPeriod(RecapPeriod.month, DateTime(2026), -1),
        DateTime(2025, 12),
      );
      expect(shiftPeriod(RecapPeriod.year, DateTime(2026), 1), DateTime(2027));
      expect(
        periodStart(RecapPeriod.month, DateTime(2026, 10, 15)),
        DateTime(2026, 10),
      );
    });

    test('last year all January, last month in the first week', () {
      expect(recapBannerFor(DateTime(2027, 1, 3)), (
        period: RecapPeriod.year,
        start: DateTime(2026),
      ));
      expect(recapBannerFor(DateTime(2027, 1, 31))?.period, RecapPeriod.year);
      expect(recapBannerFor(DateTime(2026, 10, 7)), (
        period: RecapPeriod.month,
        start: DateTime(2026, 9),
      ));
      expect(recapBannerFor(DateTime(2026, 10, 8)), isNull);
    });
  });

  group('recapStory', () {
    test('one card per stat, in order', () {
      final cards = recapStory(_recap(), groupName: 'Movie night');

      expect(cards.map((c) => c.eyebrow), [
        'Recap',
        'Memories made',
        'Most active planner',
        'Top category',
        'The wheel decided',
        'Worth the wait',
        'Still on the wish list',
        'In numbers',
      ]);
      expect(cards.first.headline, 'Your October 2026');
      expect(cards.first.subtitle, 'with Movie night');
      expect(cards[1].number, 2);
      expect(cards[1].lines.map((l) => l.text), ['Picnic', 'Board games']);
      expect(cards[2].headline, 'Bea');
      expect(cards[2].subtitle, '6 plans · 3 ideas · 2 events · 1 done');
      expect(cards[2].lines.single.text, '2. Ana · 2 plans');
      expect(cards[3].color, '#2E7D32');
      expect(cards[5].number, 120);
      expect(cards.last.headline, "That's a wrap");
      expect(cards.last.lines.map((l) => l.text), [
        '5 ideas added',
        '2 events planned',
        '1 poll created',
      ]);
    });

    test('a year has its busiest month; a running period says so', () {
      final cards = recapStory(
        _recap(
          period: 'year',
          complete: false,
          busiestMonth: {'month': '2026-06-01', 'count': 4},
        ),
        groupName: 'Movie night',
      );

      expect(cards.first.headline, 'Your 2026');
      expect(
        cards.first.lines.single.text,
        "So far: this year isn't over yet.",
      );
      final busiest = cards.firstWhere((c) => c.eyebrow == 'Busiest month');
      expect(busiest.headline, 'June');
      expect(busiest.subtitle, '4 memories');
      expect(cards.last.headline, 'So far');
    });

    test('many memories are summed up', () {
      final cards = recapStory(
        _recap(
          memories: [
            for (var i = 0; i < 9; i++) recapActivityJson(title: 'Memory $i'),
          ],
        ),
        groupName: 'Movie night',
      );

      expect(cards[1].lines, hasLength(7));
      expect(cards[1].lines.last.text, '…and 3 more');
    });

    test('a quiet period gets a single card after the intro', () {
      final cards = recapStory(
        _recap(
          memories: [],
          ideasAdded: 0,
          eventsPlanned: 0,
          pollsCreated: 0,
          wheelDecisions: 0,
        ),
        groupName: 'Movie night',
      );

      expect(cards.map((c) => c.headline), [
        'Your October 2026',
        'A quiet month',
      ]);
    });
  });

  group('RecapScreen', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend()..stubGroup();
      backend.adapter.onJson('GET', ApiPaths.recap(Ids.groupId), recapJson());
    });

    Future<ProviderContainer> open(
      WidgetTester tester,
      String location, {
      DateTime? today,
    }) async {
      if (today != null) backend.today = today;
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      return await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: location,
      );
    }

    Map<String, List<String>> lastQuery() => backend.adapter
        .requestsTo('GET', ApiPaths.recap(Ids.groupId))
        .last
        .queryParametersAll;

    testWidgets('pages through the story and opens an activity', (
      tester,
    ) async {
      final container = await open(
        tester,
        Routes.groupRecap(Ids.groupId, start: '2026-10-01'),
      );

      expect(lastQuery(), {
        'period': ['month'],
        'start': ['2026-10-01T00:00:00.000Z'],
      });
      expect(find.text('Your October 2026'), findsOneWidget);
      expect(find.text('with Movie night'), findsOneWidget);
      expect(find.text('1 / 8'), findsOneWidget);

      await tester.tap(find.byTooltip('Next card'));
      await tester.pumpAndSettle();
      expect(find.text('MEMORIES MADE'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // counted up
      expect(find.text('Board games'), findsOneWidget);

      // Tapping the right side moves on too.
      final card = tester.getRect(find.byType(RecapCardView));
      await tester.tapAt(Offset(card.right - 20, card.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('Bea'), findsOneWidget);
      // ...and the left side goes back.
      await tester.tapAt(Offset(card.left + 20, card.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('MEMORIES MADE'), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byTooltip('Next card'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Escape room'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Open'));
      await tester.pumpAndSettle();
      expect(
        currentLocation(container),
        Routes.activity(Ids.groupId, Ids.activityId),
      );
    });

    testWidgets('switches periods from the loaded one', (tester) async {
      await open(tester, Routes.groupRecap(Ids.groupId));
      expect(lastQuery(), {
        'period': ['month'],
      });

      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(lastQuery()['start'], ['2026-09-01T00:00:00.000Z']);

      backend.adapter.onJson(
        'GET',
        ApiPaths.recap(Ids.groupId),
        recapJson(period: 'year', start: '2026-01-01', end: '2027-01-01'),
      );
      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(lastQuery(), {
        'period': ['year'],
        'start': ['2026-01-01T00:00:00.000Z'],
      });
      expect(find.text('Your 2026'), findsOneWidget);
    });

    testWidgets('shares the card on screen as an image', (tester) async {
      await open(tester, Routes.groupRecap(Ids.groupId, start: '2026-10-01'));

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Share this card'));
        // Rendering the image happens off the fake clock.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      final shared = backend.recapSharer.shared.single;
      expect(shared.text, 'Our October 2026 with Movie night, on Friends');
      // A PNG.
      expect(shared.png.sublist(1, 4), 'PNG'.codeUnits);
    });

    testWidgets('the banner opens last month and can be dismissed', (
      tester,
    ) async {
      final container = await open(
        tester,
        Routes.groupBacklog(Ids.groupId),
        today: DateTime(2026, 10, 3),
      );

      expect(find.text('Your September 2026 with Movie night'), findsOneWidget);
      await tester.tap(find.text('Your September 2026 with Movie night'));
      await tester.pumpAndSettle();
      expect(
        currentLocation(container),
        Routes.groupRecap(Ids.groupId, start: '2026-09-01'),
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(RecapBanner),
          matching: find.byTooltip('Dismiss'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecapBanner), findsOneWidget);
      expect(find.text('Your September 2026 with Movie night'), findsNothing);
    });

    testWidgets('no banner mid-month; the group tab links to the recap', (
      tester,
    ) async {
      final container = await open(tester, Routes.groupBacklog(Ids.groupId));
      expect(find.textContaining('Your September'), findsNothing);

      container.read(routerProvider).go(Routes.groupHub(Ids.groupId));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recap'));
      await tester.pumpAndSettle();
      expect(currentLocation(container), Routes.groupRecap(Ids.groupId));
      expect(find.byType(RecapScreen), findsOneWidget);
    });
  });
}
