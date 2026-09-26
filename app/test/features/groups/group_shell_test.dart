import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/presentation/backlog_screen.dart';
import 'package:friends/features/calendar/presentation/calendar_screen.dart';
import 'package:friends/features/groups/presentation/group_hub_screen.dart';
import 'package:friends/features/groups/presentation/group_shell.dart';
import 'package:friends/features/groups/presentation/groups_list_screen.dart';
import 'package:friends/features/wheel/presentation/wheel_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  Future<ProviderContainer> open(WidgetTester tester, String location) =>
      tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: location,
      );

  group('GroupShell', () {
    testWidgets('/groups/:id opens the backlog tab', (tester) async {
      backend.stubGroup();

      final container = await open(tester, Routes.group(Ids.groupId));

      expect(currentLocation(container), '/groups/${Ids.groupId}/backlog');
      expect(find.byType(GroupShell), findsOneWidget);
      expect(find.byType(BacklogScreen), findsOneWidget);
      // The switcher shows the group; the avatar opens the profile.
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.byTooltip('Profile'), findsOneWidget);
    });

    testWidgets('the bottom navigation switches between the four tabs', (
      tester,
    ) async {
      backend.stubGroup();
      final container = await open(tester, Routes.groupBacklog(Ids.groupId));

      for (final (label, path, screen) in [
        ('Calendar', 'calendar', CalendarScreen),
        ('Wheel', 'wheel', WheelScreen),
        ('Group', 'group', GroupHubScreen),
        ('Backlog', 'backlog', BacklogScreen),
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();

        expect(currentLocation(container), '/groups/${Ids.groupId}/$path');
        expect(find.byType(screen), findsOneWidget);
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(
          bar.selectedIndex,
          GroupTab.values.indexWhere((t) => t.segment == path),
        );
      }
      // One group fetch for all the tabs: the shell stays.
      expect(
        backend.adapter.requestsTo('GET', ApiPaths.group(Ids.groupId)),
        hasLength(1),
      );
    });

    testWidgets('the theme is seeded from the group colour', (tester) async {
      backend.stubGroup(group: groupJson(color: '#43A047'));
      await open(tester, Routes.groupBacklog(Ids.groupId));

      final context = tester.element(find.byType(BacklogScreen));
      expect(
        Theme.of(context).colorScheme.primary,
        ColorScheme.fromSeed(seedColor: const Color(0xFF43A047)).primary,
      );
    });

    testWidgets('remembers the group as the last one opened', (tester) async {
      backend.stubGroup();
      await open(tester, Routes.groupBacklog(Ids.groupId));

      expect(backend.lastGroup.groupId, Ids.groupId);
    });

    testWidgets('the switcher lists my groups and switches', (tester) async {
      backend
        ..stubGroup()
        ..stubGroups([
          groupSummaryJson(),
          groupSummaryJson(id: Ids.otherGroupId, name: 'Hikes'),
        ])
        ..adapter.onJson(
          'GET',
          ApiPaths.group(Ids.otherGroupId),
          groupJson(id: Ids.otherGroupId, name: 'Hikes'),
        );
      final container = await open(tester, Routes.groupBacklog(Ids.groupId));

      await tester.tap(find.byTooltip('Switch group'));
      await tester.pumpAndSettle();
      expect(find.text('All groups'), findsOneWidget);
      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Join with code'), findsOneWidget);
      await tester.tap(find.text('Hikes'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/groups/${Ids.otherGroupId}/backlog');
      expect(find.text('Hikes'), findsOneWidget);
      expect(backend.lastGroup.groupId, Ids.otherGroupId);

      await tester.tap(find.byTooltip('Switch group'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All groups'));
      await tester.pumpAndSettle();
      expect(currentLocation(container), '/groups');
      expect(find.byType(GroupsListScreen), findsOneWidget);
    });

    testWidgets('a 404 shows "Group not found" with a way back', (
      tester,
    ) async {
      backend.stubGroups([]);
      final container = await open(tester, Routes.groupBacklog(Ids.groupId));

      expect(find.text('Group not found'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(backend.lastGroup.groupId, isNull);

      await tester.tap(find.text('Back to my groups'));
      await tester.pumpAndSettle();
      expect(currentLocation(container), '/groups');
    });

    testWidgets('a group ID that is not a UUID is not found either', (
      tester,
    ) async {
      backend.adapter.onProblem(
        'GET',
        ApiPaths.group('nope'),
        422,
        ErrorCodes.validationError,
        errors: [
          {
            'field': 'path.group_id',
            'message': 'Input should be a valid UUID',
            'type': 'uuid_parsing',
          },
        ],
      );

      await open(tester, Routes.groupBacklog('nope'));

      expect(find.text('Group not found'), findsOneWidget);
    });

    testWidgets('a 404 from a group endpoint in a tab shows "Group not '
        'found" too', (tester) async {
      backend
        ..stubGroup()
        ..adapter.onProblem(
          'GET',
          ApiPaths.members(Ids.groupId),
          404,
          ErrorCodes.notFound,
        );

      await open(tester, Routes.groupHub(Ids.groupId));

      expect(find.text('Group not found'), findsOneWidget);
    });

    testWidgets('other errors offer Retry', (tester) async {
      backend.adapter.onProblem(
        'GET',
        ApiPaths.group(Ids.groupId),
        500,
        ErrorCodes.internalError,
      );
      await open(tester, Routes.groupBacklog(Ids.groupId));
      expect(find.text('Retry'), findsOneWidget);

      backend.stubGroup();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(BacklogScreen), findsOneWidget);
    });
  });
}
