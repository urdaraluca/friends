import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/calendar/domain/rrule_spec.dart';
import 'package:friends/features/calendar/presentation/calendar_screen.dart';
import 'package:friends/features/calendar/presentation/widgets/calendar_view.dart';
import 'package:friends/features/calendar/presentation/widgets/recurrence_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

/// Holds a RecurrencePicker's spec, like the event form does.
class _PickerHarness extends StatefulWidget {
  const new({required this.start, required this.onRule});

  final DateTime start;
  final ValueChanged<String> onRule;

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  late RecurrenceSpec _spec = RecurrenceSpec.startingOn(
    RepeatFrequency.weekly,
    widget.start,
  );

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: RecurrencePicker(
        spec: _spec,
        start: widget.start,
        onChanged: (spec) {
          setState(() => _spec = spec);
          widget.onRule(spec.toRule(allDay: false));
        },
      ),
    );
  }
}

void main() {
  group('RecurrencePicker', () {
    Future<List<String>> pumpPicker(WidgetTester tester, DateTime start) async {
      final rules = <String>[];
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpApp(
        Scaffold(
          body: _PickerHarness(start: start, onRule: rules.add),
        ),
      );
      return rules;
    }

    testWidgets('weekly days, monthly day/last day/weekday, count', (
      tester,
    ) async {
      // Thursday 15 October 2026: the third Thursday.
      final rules = await pumpPicker(tester, DateTime(2026, 10, 15));

      await tester.tap(find.widgetWithText(FilterChip, 'Mon'));
      await tester.pump();
      expect(rules.last, 'FREQ=WEEKLY;BYDAY=MO,TH');

      await tester.tap(find.text('Monthly'));
      await tester.pump();
      expect(rules.last, 'FREQ=MONTHLY;BYMONTHDAY=15');

      await tester.tap(find.text('On the last day'));
      await tester.pump();
      expect(rules.last, 'FREQ=MONTHLY;BYMONTHDAY=-1');

      await tester.tap(find.text('On the third Thursday'));
      await tester.pump();
      expect(rules.last, 'FREQ=MONTHLY;BYDAY=3TH');

      await tester.tap(find.byType(Radio<String>).last); // "After N times"
      await tester.pump();
      expect(rules.last, 'FREQ=MONTHLY;BYDAY=3TH;COUNT=10');
      expect(
        find.text('Every month on the third Thursday, 10 times'),
        findsOneWidget,
      );
    });

    testWidgets('after the 28th a day number is not offered', (tester) async {
      final rules = await pumpPicker(tester, DateTime(2026, 10, 30));

      await tester.tap(find.text('Monthly'));
      await tester.pump();

      // The default is the last day, and "On day 30" is disabled.
      expect(rules.last, 'FREQ=MONTHLY;BYMONTHDAY=-1');
      expect(find.text('Not every month has this day'), findsOneWidget);
      // 30 October 2026 is the last Friday of the month.
      expect(find.text('On the last Friday'), findsOneWidget);
    });
  });

  group('CalendarScreen', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
    });

    Future<ProviderContainer> openCalendar(
      WidgetTester tester,
      List<Map<String, Object?>> occurrences,
    ) async {
      backend.adapter.onJson(
        'GET',
        ApiPaths.calendar(Ids.groupId),
        calendarJson(occurrences),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      return await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.calendar(Ids.groupId, day: '2026-10-15'),
      );
    }

    testWidgets('asks for the visible grid in the device timezone', (
      tester,
    ) async {
      await openCalendar(tester, []);

      final query = backend.adapter
          .requestsTo('GET', ApiPaths.calendar(Ids.groupId))
          .last
          .queryParametersAll;
      // October 2026: the grid starts on Monday 28 September, six weeks.
      expect(query['from'], ['2026-09-28T00:00:00.000Z']);
      expect(query['to'], ['2026-11-09T00:00:00.000Z']);
      expect(query['tz'], ['Europe/Bucharest']);
      expect(query['kinds'], isNull);
      expect(find.byType(CalendarView), findsOneWidget);
      expect(find.text('Nothing planned.'), findsOneWidget);
    });

    testWidgets('the day agenda lists all-day items before timed ones', (
      tester,
    ) async {
      final evening = DateTime(2026, 10, 15, 19);
      await openCalendar(tester, [
        occurrenceJson(
          kind: 'recurring',
          startsAt: evening.toUtc().toIso8601String(),
          endsAt: evening
              .add(const Duration(hours: 3))
              .toUtc()
              .toIso8601String(),
        ),
        occurrenceJson(
          title: 'Bea',
          kind: 'birthday',
          source: 'member_birthday',
          userId: Ids.beaId,
          color: null,
          startDate: '2026-10-15',
        ),
        occurrenceJson(
          title: 'Trip',
          startDate: '2026-10-14',
          endDate: '2026-10-16',
        ),
      ]);

      final agenda = tester.widgetList<AgendaTile>(find.byType(AgendaTile));
      expect(agenda.map((t) => t.occurrence.title), [
        'Bea',
        'Trip',
        'Game night',
      ]);
      expect(find.text("Bea's birthday"), findsOneWidget);
      expect(find.text('19:00–22:00'), findsOneWidget); // no timezone label
      expect(find.text('14 Oct – 16 Oct'), findsOneWidget);
      // Markers: a cake for the birthday.
      expect(find.text('🎂'), findsWidgets);
    });

    testWidgets('kind chips filter the request', (tester) async {
      await openCalendar(tester, []);

      await tester.tap(find.widgetWithText(FilterChip, 'Birthdays'));
      await tester.pumpAndSettle();

      final query = backend.adapter
          .requestsTo('GET', ApiPaths.calendar(Ids.groupId))
          .last
          .queryParametersAll;
      expect(query['kinds'], ['one_time', 'recurring']);
    });
  });

  group('EventForm', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
    });

    Future<void> open(WidgetTester tester, String location) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: location,
      );
    }

    testWidgets('"Schedule it" creates a weekly event linked to the idea', (
      tester,
    ) async {
      backend.adapter
        ..onJson(
          'GET',
          ApiPaths.activity(Ids.activityId),
          activityJson(title: 'Board games'),
        )
        ..onJson(
          'POST',
          ApiPaths.events(Ids.groupId),
          eventJson(activityId: Ids.activityId),
          status: 201,
        )
        ..onJson(
          'GET',
          ApiPaths.event(Ids.eventId),
          eventJson(activityId: Ids.activityId),
        );
      await open(
        tester,
        Routes.newEvent(
          Ids.groupId,
          activityId: Ids.activityId,
          date: '2026-10-15',
        ),
      );

      expect(find.widgetWithText(TextFormField, 'Board games'), findsOneWidget);
      expect(
        find.text('Scheduling this idea marks it as scheduled'),
        findsOneWidget,
      );
      await tester.tap(find.text('Repeats'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.events(Ids.groupId))
          .single
          .jsonMap;
      expect(body['kind'], 'recurring');
      expect(body['title'], 'Board games');
      expect(body['rrule'], 'FREQ=WEEKLY;BYDAY=TH');
      expect(body['activity_id'], Ids.activityId);
      expect(body['all_day'], isFalse);
      // 19:00 on 15 October in the device's zone, sent as UTC.
      expect(
        body['starts_at'],
        DateTime(2026, 10, 15, 19).toUtc().toIso8601String(),
      );
      expect(body['start_date'], isNull);
      // Then the new event opens.
      expect(find.text('Every week on Thursday'), findsOneWidget);
    });

    testWidgets('a birthday is all-day with no end or rule', (tester) async {
      backend.adapter
        ..onJson(
          'POST',
          ApiPaths.events(Ids.groupId),
          eventJson(
            kind: 'birthday',
            allDay: true,
            startDate: '2026-10-15',
            rrule: 'FREQ=YEARLY',
          ),
          status: 201,
        )
        ..onJson(
          'GET',
          ApiPaths.event(Ids.eventId),
          eventJson(
            kind: 'birthday',
            allDay: true,
            startDate: '2026-10-15',
            rrule: 'FREQ=YEARLY',
          ),
        );
      await open(tester, Routes.newEvent(Ids.groupId, date: '2026-10-15'));

      await tester.tap(find.text('Birthday'));
      await tester.pumpAndSettle();
      expect(find.text('All day'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Whose birthday'),
        'Grandma',
      );
      await tester.tap(find.text('Add to calendar'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.events(Ids.groupId))
          .single
          .jsonMap;
      expect(body['kind'], 'birthday');
      expect(body['all_day'], isTrue);
      expect(body['start_date'], '2026-10-15T00:00:00.000Z');
      expect(body['end_date'], isNull);
      expect(body['rrule'], isNull);
      expect(body['starts_at'], isNull);
    });
  });

  group('EventDetail', () {
    testWidgets('cancel one occurrence, then restore it', (tester) async {
      final backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
      const key = '20261008T160000Z';
      var cancelled = <String>[];
      backend.adapter
        ..on(
          'GET',
          ApiPaths.event(Ids.eventId),
          (_) => FakeReply.json(eventJson(cancelled: cancelled)),
        )
        ..on('DELETE', ApiPaths.occurrence(Ids.eventId, key), (_) {
          cancelled = [key];
          return const FakeReply.noContent();
        })
        ..on('POST', '${ApiPaths.occurrence(Ids.eventId, key)}/restore', (_) {
          cancelled = [];
          return const FakeReply.noContent();
        });
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.event(Ids.groupId, Ids.eventId, occurrence: key),
      );

      expect(find.text('Every week on Thursday'), findsOneWidget);
      await tester.tap(find.text('Cancel this occurrence'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel this occurrence'), findsNothing);
      expect(find.text('Cancelled'), findsOneWidget);
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel this occurrence'), findsOneWidget);
      expect(
        backend.adapter.requests.map((r) => '${r.method} ${r.path}'),
        containsAll([
          'DELETE ${ApiPaths.occurrence(Ids.eventId, key)}',
          'POST ${ApiPaths.occurrence(Ids.eventId, key)}/restore',
        ]),
      );
    });
  });
}
