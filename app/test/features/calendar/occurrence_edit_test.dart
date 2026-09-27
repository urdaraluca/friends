import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/calendar/presentation/calendar_screen.dart';
import 'package:friends/features/calendar/presentation/event_detail_screen.dart';
import 'package:friends/features/calendar/presentation/occurrence_edit_page.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

const _key = '20261008T160000Z';

Map<String, Object?> _edit({String? title, String? startsAt, String? endsAt}) =>
    {
      'occurrence_key': _key,
      'title': title,
      'starts_at': startsAt,
      'ends_at': endsAt,
      'start_date': null,
      'end_date': null,
    };

void main() {
  group('occurrence helpers', () {
    test('an edit wins over the series', () {
      final series = Event.fromJson(eventJson());
      final edited = Event.fromJson(
        eventJson(
          edited: [
            _edit(
              title: 'Catan night',
              startsAt: '2026-10-09T17:00:00Z',
              endsAt: '2026-10-09T20:00:00Z',
            ),
          ],
        ),
      );

      expect(occurrenceTitle(series, _key), 'Game night');
      expect(occurrenceTitle(edited, _key), 'Catan night');
      expect(occurrenceTitle(edited, '20261015T160000Z'), 'Game night');
      expect(
        occurrenceTimes(edited, _key).start,
        DateTime.utc(2026, 10, 9, 17),
      );
      expect(
        occurrenceTimes(edited, _key, series: true).start,
        DateTime.utc(2026, 10, 8, 16),
      );
      // A title-only edit keeps the series' time.
      final renamed = Event.fromJson(
        eventJson(edited: [_edit(title: 'Catan night')]),
      );
      expect(
        occurrenceTimes(renamed, _key).start,
        DateTime.utc(2026, 10, 8, 16),
      );
    });
  });

  group('EventDetail', () {
    late TestBackend backend;
    late List<Map<String, Object?>> edits;

    setUp(() {
      edits = [];
      backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
      backend.adapter
        ..on(
          'GET',
          ApiPaths.event(Ids.eventId),
          (_) => FakeReply.json(eventJson(edited: edits)),
        )
        ..on('PUT', ApiPaths.occurrence(Ids.eventId, _key), (request) {
          final body = request.jsonMap;
          edits = [
            _edit(
              title: body['title'] as String?,
              startsAt: body['starts_at'] as String?,
              endsAt: body['ends_at'] as String?,
            ),
          ];
          return FakeReply.json(eventJson(edited: edits));
        })
        ..on('POST', '${ApiPaths.occurrence(Ids.eventId, _key)}/restore', (_) {
          edits = [];
          return const FakeReply.noContent();
        });
    });

    Future<ProviderContainer> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      return await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.event(Ids.groupId, Ids.eventId, occurrence: _key),
      );
    }

    testWidgets('rename one occurrence, then undo it', (tester) async {
      await open(tester);

      await tester.tap(find.text('Change this occurrence'));
      await tester.pumpAndSettle();
      expect(find.byType(OccurrenceEditPage), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Catan night',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('PUT', ApiPaths.occurrence(Ids.eventId, _key))
          .single
          .jsonMap;
      expect(body['title'], 'Catan night');
      expect(body['starts_at'], isNull);
      expect(body['start_date'], isNull);
      expect(find.byType(OccurrenceEditPage), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Catan night'),
        ),
        findsOneWidget,
      );
      expect(find.text('Changed for this time only'), findsWidgets);

      await tester.tap(find.widgetWithText(TextButton, 'Undo'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo(
          'POST',
          '${ApiPaths.occurrence(Ids.eventId, _key)}/restore',
        ),
        hasLength(1),
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Game night'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('saving the series values goes back to the series', (
      tester,
    ) async {
      edits = [_edit(title: 'Catan night')];
      await open(tester);

      await tester.tap(find.text('Change this occurrence'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Game night',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo(
          'PUT',
          ApiPaths.occurrence(Ids.eventId, _key),
        ),
        isEmpty,
      );
      expect(
        backend.adapter.requestsTo(
          'POST',
          '${ApiPaths.occurrence(Ids.eventId, _key)}/restore',
        ),
        hasLength(1),
      );
    });

    testWidgets('a moved occurrence shows its new time', (tester) async {
      final start = DateTime(2026, 10, 9, 20);
      edits = [
        _edit(
          startsAt: start.toUtc().toIso8601String(),
          endsAt: start.add(const Duration(hours: 3)).toUtc().toIso8601String(),
        ),
      ];
      await open(tester);

      expect(find.textContaining('Friday 9 October 2026'), findsOneWidget);
      expect(find.textContaining('20:00–23:00'), findsOneWidget);
    });
  });

  testWidgets('the agenda marks an edited occurrence', (tester) async {
    await tester.pumpApp(
      Scaffold(
        body: AgendaTile(
          groupId: Ids.groupId,
          occurrence: Occurrence.fromJson(
            occurrenceJson(
              startsAt: '2026-10-08T16:00:00Z',
              endsAt: '2026-10-08T19:00:00Z',
              kind: 'recurring',
              edited: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.edit_calendar_outlined), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsNothing);
  });
}
