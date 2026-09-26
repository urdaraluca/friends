import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/groups/presentation/group_form_screen.dart';
import 'package:friends/features/groups/presentation/groups_list_screen.dart';
import 'package:friends/features/invites/presentation/join_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  Future<ProviderContainer> openList(WidgetTester tester) =>
      tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.groups,
      );

  group('GroupsListScreen', () {
    testWidgets('shows a card per group: emoji, name, members, my role', (
      tester,
    ) async {
      backend.stubGroups([
        groupSummaryJson(
          name: 'Hikes',
          emoji: '🥾',
          color: '#43A047',
          memberCount: 5,
          myRole: 'owner',
        ),
        groupSummaryJson(id: Ids.otherGroupId, memberCount: 1, myRole: 'admin'),
      ]);

      await openList(tester);

      expect(find.byType(GroupCard), findsNWidgets(2));
      expect(find.text('Hikes'), findsOneWidget);
      expect(find.text('🥾'), findsOneWidget);
      expect(find.text('5 members'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      // No emoji: the initial on the group's colour.
      expect(find.text('Movie night'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('1 member'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      final avatar = tester.widget<CircleAvatar>(
        find.ancestor(of: find.text('🥾'), matching: find.byType(CircleAvatar)),
      );
      expect(avatar.backgroundColor, const Color(0xFF43A047));
    });

    testWidgets('a card opens the group', (tester) async {
      backend.stubGroup();
      final container = await openList(tester);

      await tester.tap(find.text('Movie night'));
      await tester.pumpAndSettle();

      expect(currentLocation(container), '/groups/${Ids.groupId}/backlog');
    });

    testWidgets('pull to refresh fetches the groups again', (tester) async {
      var fetches = 0;
      backend.adapter.on('GET', ApiPaths.groups, (_) {
        fetches++;
        return FakeReply.json([
          if (fetches > 1) groupSummaryJson(name: 'New group $fetches'),
        ]);
      });
      await openList(tester);
      expect(find.text('No groups yet'), findsOneWidget);

      await tester.fling(
        find.text('No groups yet'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(fetches, 2);
      expect(find.text('New group 2'), findsOneWidget);
    });

    testWidgets('an error offers Retry', (tester) async {
      backend.adapter.onProblem('GET', ApiPaths.groups, 500, 'internal_error');
      await openList(tester);
      expect(find.text('Retry'), findsOneWidget);

      backend.stubGroups([groupSummaryJson()]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Movie night'), findsOneWidget);
    });

    testWidgets('the FAB opens the create form', (tester) async {
      backend.stubGroups([]);
      await openList(tester);

      await tester.tap(find.text('New group'));
      await tester.pumpAndSettle();

      expect(find.byType(GroupFormScreen), findsOneWidget);
      // Pushed: back returns to the list.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(GroupsListScreen), findsOneWidget);
    });

    testWidgets('the menu joins with a code: it opens the invite preview', (
      tester,
    ) async {
      backend
        ..stubGroups([groupSummaryJson()])
        ..adapter.onJson(
          'GET',
          ApiPaths.invitePreview('ABCDEFGH1K'),
          invitePreviewJson(code: 'ABCDEFGH1K', groupName: 'Board games'),
        );
      await openList(tester);

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join with code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'abcd-efgh-ik');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(JoinScreen), findsOneWidget);
      expect(find.text('Board games'), findsOneWidget);
    });
  });
}
