import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/date_only.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/availability/domain/availability_draft.dart';
import 'package:friends/features/availability/domain/month_days.dart';
import 'package:friends/features/availability/presentation/group_availability_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

AvailabilityEntry _entry(
  String date,
  AvailabilitySlot slot,
  AvailabilityStatus status,
) => AvailabilityEntry(date: DateOnly.parse(date), slot: slot, status: status);

void main() {
  group('month grid', () {
    test('October 2026 runs from Monday 28 September to Sunday 1 November', () {
      final days = monthGridDays(DateTime(2026, 10));
      expect(days, hasLength(35));
      expect(days.first, DateTime(2026, 9, 28));
      expect(days.last, DateTime(2026, 11));
      final range = gridRange(DateTime(2026, 10));
      expect(range.from, DateTime.utc(2026, 9, 28));
      expect(range.to, DateTime.utc(2026, 11, 2));
    });

    test('six weeks when the month needs them, days in order', () {
      // August 2026 starts on a Saturday and ends on a Monday.
      final days = monthGridDays(DateTime(2026, 8));
      expect(days, hasLength(42));
      expect(days.first, DateTime(2026, 7, 27));
      expect(days.last, DateTime(2026, 9, 6));
      for (var i = 1; i < days.length; i++) {
        expect(
          days[i].difference(days[i - 1]).inHours,
          inInclusiveRange(23, 25),
        );
        expect(days[i].day != days[i - 1].day, isTrue);
      }
    });
  });

  group('AvailabilityDraft', () {
    final wed = DateTime(2026, 10, 7);

    test('a tap cycles free, maybe, busy, not set', () {
      var status = AvailabilityDraft.next(null);
      expect(status, AvailabilityStatus.free);
      status = AvailabilityDraft.next(status);
      expect(status, AvailabilityStatus.maybe);
      status = AvailabilityDraft.next(status);
      expect(status, AvailabilityStatus.busy);
      expect(AvailabilityDraft.next(status), isNull);
    });

    test('a part of the day falls back to the all-day answer', () {
      final draft = AvailabilityDraft([
        _entry('2026-10-07', AvailabilitySlot.allDay, AvailabilityStatus.busy),
        _entry('2026-10-07', AvailabilitySlot.evening, AvailabilityStatus.free),
      ]);
      expect(
        draft.effective(wed, AvailabilitySlot.morning),
        AvailabilityStatus.busy,
      );
      expect(draft.status(wed, AvailabilitySlot.morning), isNull);
      expect(
        draft.effective(wed, AvailabilitySlot.evening),
        AvailabilityStatus.free,
      );
      expect(
        draft.effective(DateTime(2026, 10, 8), AvailabilitySlot.allDay),
        isNull,
      );
    });

    test('dirty only when something differs from what was saved', () {
      final draft = AvailabilityDraft([
        _entry('2026-10-07', AvailabilitySlot.allDay, AvailabilityStatus.free),
      ]);
      expect(draft.dirty, isFalse);
      draft.set(wed, AvailabilitySlot.allDay, AvailabilityStatus.maybe);
      expect(draft.dirty, isTrue);
      draft.set(wed, AvailabilitySlot.allDay, AvailabilityStatus.free);
      expect(draft.dirty, isFalse);
      draft.set(wed, AvailabilitySlot.allDay, null);
      expect(draft.dirty, isTrue);
    });

    test('copyWeek replaces every slot of the target week', () {
      final draft = AvailabilityDraft([
        _entry('2026-10-05', AvailabilitySlot.allDay, AvailabilityStatus.busy),
        _entry('2026-10-07', AvailabilitySlot.evening, AvailabilityStatus.free),
        _entry('2026-10-13', AvailabilitySlot.allDay, AvailabilityStatus.free),
      ])..copyWeek(DateTime(2026, 10, 5), DateTime(2026, 10, 12));

      final entries = draft.entries(
        DateTime.utc(2026, 10, 12),
        DateTime.utc(2026, 10, 19),
      );
      expect(entries.map((e) => (DateOnly.format(e.date), e.slot, e.status)), [
        ('2026-10-12', AvailabilitySlot.allDay, AvailabilityStatus.busy),
        ('2026-10-14', AvailabilitySlot.evening, AvailabilityStatus.free),
      ]);
    });

    test('entries keeps the range and sends UTC midnights', () {
      final draft = AvailabilityDraft([
        _entry('2026-09-27', AvailabilitySlot.allDay, AvailabilityStatus.free),
        _entry('2026-09-28', AvailabilitySlot.allDay, AvailabilityStatus.free),
        _entry('2026-11-02', AvailabilitySlot.allDay, AvailabilityStatus.free),
      ]);
      final range = gridRange(DateTime(2026, 10));
      final entries = draft.entries(range.from, range.to);
      expect(entries, hasLength(1));
      expect(entries.single.date, DateTime.utc(2026, 9, 28));
    });
  });

  group('MyAvailabilityScreen', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend();
    });

    Future<ProviderContainer> open(
      WidgetTester tester,
      List<Map<String, Object?>> entries,
    ) async {
      backend.adapter
        ..onJson('GET', ApiPaths.myAvailability, myAvailabilityJson(entries))
        ..on(
          'PUT',
          ApiPaths.myAvailability,
          (request) => FakeReply.json(
            myAvailabilityJson([
              for (final entry
                  in (request.jsonMap['entries']! as List)
                      .cast<Map<String, Object?>>())
                {...entry, 'date': (entry['date']! as String).substring(0, 10)},
            ]),
          ),
        );
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      return await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.myAvailabilityFor(month: '2026-10-15'),
      );
    }

    Finder day(String date) => find.byKey(ValueKey('day-$date'));

    List<Object?> savedEntries() =>
        backend.adapter
                .requestsTo('PUT', ApiPaths.myAvailability)
                .last
                .jsonMap['entries']!
            as List<Object?>;

    testWidgets('loads the grid, cycles days per slot and saves them', (
      tester,
    ) async {
      await open(tester, [availabilityEntryJson('2026-10-03')]);

      final query = backend.adapter
          .requestsTo('GET', ApiPaths.myAvailability)
          .single
          .queryParametersAll;
      expect(query['from'], ['2026-09-28T00:00:00.000Z']);
      expect(query['to'], ['2026-11-02T00:00:00.000Z']);
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(day('2026-10-05')); // not set -> free
      await tester.tap(day('2026-10-03')); // free -> maybe
      await tester.tap(find.widgetWithText(ChoiceChip, 'Evening'));
      await tester.pump();
      await tester.tap(day('2026-10-06')); // evening: free
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('PUT', ApiPaths.myAvailability)
          .single
          .jsonMap;
      expect(body['from_date'], '2026-09-28T00:00:00.000Z');
      expect(body['to_date'], '2026-11-02T00:00:00.000Z');
      expect(body['entries'], [
        {
          'date': '2026-10-03T00:00:00.000Z',
          'slot': 'all_day',
          'status': 'maybe',
        },
        {
          'date': '2026-10-05T00:00:00.000Z',
          'slot': 'all_day',
          'status': 'free',
        },
        {
          'date': '2026-10-06T00:00:00.000Z',
          'slot': 'evening',
          'status': 'free',
        },
      ]);
      expect(find.text('Availability saved.'), findsOneWidget);
      // Saved: nothing left to save.
      final save = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets("dragging paints the first day's new answer", (tester) async {
      await open(tester, [availabilityEntryJson('2026-10-20', status: 'busy')]);

      final gesture = await tester.startGesture(
        tester.getCenter(day('2026-10-19')),
      );
      // One move across two cells: the day in between is painted too.
      await gesture.moveTo(tester.getCenter(day('2026-10-21')));
      await gesture.moveTo(tester.getCenter(day('2026-10-28')));
      await gesture.up();
      await tester.pump();

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();
      expect(savedEntries(), [
        for (final date in ['19', '20', '21', '28'])
          {
            'date': '2026-10-${date}T00:00:00.000Z',
            'slot': 'all_day',
            'status': 'free',
          },
      ]);
    });

    testWidgets('"Copy last week" copies the week above', (tester) async {
      await open(tester, [
        availabilityEntryJson('2026-10-05', status: 'busy'),
        availabilityEntryJson('2026-10-07', slot: 'evening'),
      ]);

      await tester.tap(find.byKey(const ValueKey('copy-week-2026-10-12')));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(savedEntries(), [
        {
          'date': '2026-10-05T00:00:00.000Z',
          'slot': 'all_day',
          'status': 'busy',
        },
        {
          'date': '2026-10-07T00:00:00.000Z',
          'slot': 'evening',
          'status': 'free',
        },
        {
          'date': '2026-10-12T00:00:00.000Z',
          'slot': 'all_day',
          'status': 'busy',
        },
        {
          'date': '2026-10-14T00:00:00.000Z',
          'slot': 'evening',
          'status': 'free',
        },
      ]);
      // The first week has nothing above it.
      expect(find.byKey(const ValueKey('copy-week-2026-09-28')), findsNothing);
    });

    testWidgets('switching months with unsaved changes asks first', (
      tester,
    ) async {
      await open(tester, []);
      await tester.tap(day('2026-10-05'));
      await tester.pump();

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('Save your changes?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('October 2026'), findsOneWidget);

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(savedEntries(), hasLength(1));
      expect(find.text('November 2026'), findsOneWidget);
      final query = backend.adapter
          .requestsTo('GET', ApiPaths.myAvailability)
          .last
          .queryParametersAll;
      expect(query['from'], ['2026-10-26T00:00:00.000Z']);
      expect(query['to'], ['2026-12-07T00:00:00.000Z']);
    });
  });

  group('GroupAvailabilityScreen', () {
    late TestBackend backend;
    final ana = userPublicJson();
    final bea = userPublicJson(id: Ids.beaId, displayName: 'Bea');
    final cris = userPublicJson(id: Ids.crisId, displayName: 'Cris');

    setUp(() {
      backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
      backend.adapter
        ..onJson('GET', ApiPaths.calendar(Ids.groupId), calendarJson([]))
        ..onJson(
          'GET',
          ApiPaths.groupAvailability(Ids.groupId),
          groupAvailabilityJson([
            dayAvailabilityJson('2026-10-09', free: [ana], busy: 2),
            dayAvailabilityJson('2026-10-10', free: [ana, bea], maybe: [cris]),
            dayAvailabilityJson('2026-10-11', maybe: [bea], unknown: 2),
          ]),
        );
    });

    Future<ProviderContainer> open(WidgetTester tester, String location) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
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

    testWidgets('best days, who is free on a day, and "Plan it"', (
      tester,
    ) async {
      final container = await open(
        tester,
        Routes.groupAvailability(
          Ids.groupId,
          activityId: Ids.activityId,
          month: '2026-10-01',
        ),
      );

      final query = backend.adapter
          .requestsTo('GET', ApiPaths.groupAvailability(Ids.groupId))
          .single
          .queryParametersAll;
      expect(query['from'], ['2026-09-28T00:00:00.000Z']);
      expect(query['to'], ['2026-11-02T00:00:00.000Z']);

      final chips = tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((chip) => (chip.label as Text).data);
      expect(chips, [
        'Sat 10 Oct · 2 free, 1 maybe',
        'Fri 9 Oct · 1 free',
        'Sun 11 Oct · 1 maybe',
      ]);

      await tester.tap(find.text('Sat 10 Oct · 2 free, 1 maybe'));
      await tester.pumpAndSettle();
      final sheet = find.byType(DaySheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Saturday 10 October')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Free: Ana, Bea')),
        findsNWidgets(4),
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Maybe: Cris')),
        findsNWidgets(4),
      );

      await tester.tap(find.text('Plan it'));
      await tester.pumpAndSettle();
      expect(
        currentLocation(container),
        Routes.newEvent(
          Ids.groupId,
          activityId: Ids.activityId,
          date: '2026-10-10',
        ),
      );
    });

    testWidgets('busy is a count only, never names', (tester) async {
      await open(
        tester,
        Routes.groupAvailability(Ids.groupId, month: '2026-10-01'),
      );

      await tester.tap(find.byKey(const ValueKey('heat-2026-10-09')));
      await tester.pumpAndSettle();
      final sheet = find.byType(DaySheet);
      expect(
        find.descendant(of: sheet, matching: find.text('1 free · 2 busy')),
        findsNWidgets(4),
      );
      expect(
        find.descendant(of: sheet, matching: find.textContaining('Busy:')),
        findsNothing,
      );
    });

    testWidgets('the calendar links to it on the month shown', (tester) async {
      final container = await open(
        tester,
        Routes.calendar(Ids.groupId, day: '2026-10-15'),
      );

      await tester.tap(find.text('When can everyone make it?'));
      await tester.pumpAndSettle();

      expect(
        currentLocation(container),
        Routes.groupAvailability(Ids.groupId, month: '2026-10-15'),
      );
      expect(find.byType(GroupAvailabilityScreen), findsOneWidget);
    });
  });
}
