import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/calendar/presentation/my_calendar_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() {
    backend = TestBackend()..stubGroup();
    backend.adapter.onJson(
      'GET',
      ApiPaths.myCalendar,
      calendarJson([
        occurrenceJson(startDate: '2026-10-15'),
        occurrenceJson(
          title: 'Bea',
          kind: 'birthday',
          source: 'member_birthday',
          userId: Ids.beaId,
          color: null,
          startDate: '2026-10-15',
        ),
      ]),
    );
  });

  testWidgets('every group in one view; events open in their group', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: '${Routes.myCalendar}?day=2026-10-15',
    );

    final query = backend.adapter
        .requestsTo('GET', ApiPaths.myCalendar)
        .last
        .queryParametersAll;
    expect(query['from'], ['2026-09-28T00:00:00.000Z']);
    expect(query['to'], ['2026-11-09T00:00:00.000Z']);
    expect(query['tz'], ['Europe/Bucharest']);
    expect(find.byType(MyCalendarScreen), findsOneWidget);
    expect(find.text('Movie night · All day'), findsNWidgets(2));
    expect(find.text("Bea's birthday"), findsOneWidget);

    await tester.tap(find.text('Game night'));
    await tester.pumpAndSettle();
    expect(
      currentLocation(container),
      Routes.event(Ids.groupId, Ids.eventId, occurrence: '20261015'),
    );
  });

  testWidgets('the groups list links to it', (tester) async {
    final container = await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.groups,
    );

    await tester.tap(find.byTooltip('My calendar'));
    await tester.pumpAndSettle();

    expect(currentLocation(container), Routes.myCalendar);
    expect(find.byType(MyCalendarScreen), findsOneWidget);
  });
}
