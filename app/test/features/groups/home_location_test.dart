import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/backlog/presentation/backlog_placeholder_screen.dart';
import 'package:friends/features/groups/data/home_location.dart';
import 'package:friends/features/groups/presentation/groups_list_screen.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  final groups = [
    GroupSummary.fromJson(groupSummaryJson()),
    GroupSummary.fromJson(
      groupSummaryJson(id: Ids.otherGroupId, name: 'Hikes'),
    ),
  ];

  group('homeLocationFor', () {
    test('the last group while it is still in my list', () {
      expect(
        homeLocationFor(lastGroupId: Ids.otherGroupId, groups: groups),
        '/groups/${Ids.otherGroupId}/backlog',
      );
    });

    test('the groups list when the last group is gone, or unknown', () {
      expect(
        homeLocationFor(lastGroupId: 'left-long-ago', groups: groups),
        '/groups',
      );
      expect(homeLocationFor(lastGroupId: null, groups: groups), '/groups');
      expect(
        homeLocationFor(lastGroupId: Ids.groupId, groups: const []),
        '/groups',
      );
    });
  });

  group('the / redirect', () {
    late TestBackend backend;

    setUp(() => backend = TestBackend());

    Future<ProviderContainer> openHome(WidgetTester tester) =>
        tester.pumpFriendsApp(
          overrides: [
            ...backend.overrides,
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedIn()),
            ),
          ],
          location: '/',
        );

    testWidgets('opens the last group when I am still in it', (tester) async {
      backend
        ..lastGroup.groupId = Ids.groupId
        ..stubGroup();

      final container = await openHome(tester);

      expect(currentLocation(container), '/groups/${Ids.groupId}/backlog');
      expect(find.byType(BacklogPlaceholderScreen), findsOneWidget);
    });

    testWidgets('goes to the groups list when I left the last group', (
      tester,
    ) async {
      backend
        ..lastGroup.groupId = Ids.otherGroupId
        ..stubGroups([groupSummaryJson()]);

      final container = await openHome(tester);

      expect(currentLocation(container), '/groups');
      expect(find.byType(GroupsListScreen), findsOneWidget);
    });

    testWidgets('goes to the groups list without a last group', (tester) async {
      backend.stubGroups([groupSummaryJson()]);

      final container = await openHome(tester);

      expect(currentLocation(container), '/groups');
      // Without a last group, the list isn't even needed to decide.
      expect(find.text('Movie night'), findsOneWidget);
    });

    testWidgets('goes to the groups list when offline', (tester) async {
      backend
        ..lastGroup.groupId = Ids.groupId
        ..adapter.on(
          'GET',
          ApiPaths.groups,
          (_) => const FakeReply.networkError(),
        );

      final container = await openHome(tester);

      expect(currentLocation(container), '/groups');
      expect(find.text("Can't reach the server"), findsOneWidget);
    });
  });
}
