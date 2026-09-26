import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/groups/presentation/group_form_screen.dart';
import 'package:friends/features/groups/presentation/groups_list_screen.dart';
import 'package:friends/features/groups/presentation/widgets/invites_section.dart';
import 'package:friends/features/groups/presentation/widgets/transfer_ownership_dialog.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  final ana = memberJson(role: 'owner', showBirthday: false);
  final bea = memberJson(
    userId: Ids.beaId,
    displayName: 'Bea',
    birthday: {'month': 3, 'day': 12},
  );

  /// Opens the Group tab as Ana, with [role] in the group.
  Future<ProviderContainer> openHub(
    WidgetTester tester, {
    String role = 'owner',
    List<Map<String, Object?>>? members,
    List<Map<String, Object?>> invites = const [],
    bool membersCanInvite = true,
  }) {
    tester.view
      ..physicalSize = const Size(800, 3000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    backend.stubGroup(
      group: groupJson(
        myRole: role,
        memberCount: (members ?? [ana, bea]).length,
        membersCanInvite: membersCanInvite,
      ),
      members:
          members ??
          [
            {...ana, 'role': role},
            bea,
          ],
      invites: invites,
    );
    return tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.groupHub(Ids.groupId),
    );
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder sheetButton(String label) => find.descendant(
    of: find.byType(CreateInviteSheet),
    matching: find.widgetWithText(FilledButton, label),
  );

  Finder dialogButton(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(FilledButton, label),
  );

  group('members', () {
    testWidgets('shows role badges, me, and shared birthdays', (tester) async {
      await openHub(tester);

      expect(find.text('Ana (you)'), findsOneWidget);
      expect(find.text('Owner'), findsOneWidget);
      expect(find.text('Bea'), findsOneWidget);
      expect(find.text('Birthday: March 12'), findsOneWidget);
    });

    testWidgets('the owner makes a member an admin', (tester) async {
      await openHub(tester);
      backend.adapter.onJson('PUT', ApiPaths.role(Ids.groupId, Ids.beaId), {
        ...bea,
        'role': 'admin',
      });

      await tapAndSettle(tester, find.byTooltip('Actions for Bea'));
      expect(find.text('Transfer ownership'), findsOneWidget);
      expect(find.text('Remove from group'), findsOneWidget);
      await tapAndSettle(tester, find.text('Make admin'));

      expect(
        backend.adapter
            .requestsTo('PUT', ApiPaths.role(Ids.groupId, Ids.beaId))
            .single
            .jsonMap,
        {'role': 'admin'},
      );
      expect(find.text('Bea is now an admin'), findsOneWidget);
    });

    testWidgets('the owner transfers ownership after confirming', (
      tester,
    ) async {
      await openHub(tester);
      backend.adapter.onJson(
        'POST',
        ApiPaths.transfer(Ids.groupId),
        groupJson(myRole: 'admin'),
      );

      await tapAndSettle(tester, find.byTooltip('Actions for Bea'));
      await tapAndSettle(tester, find.text('Transfer ownership'));
      expect(find.text('Make Bea the owner?'), findsOneWidget);
      await tapAndSettle(tester, dialogButton('Transfer ownership'));

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.transfer(Ids.groupId))
            .single
            .jsonMap,
        {'user_id': Ids.beaId},
      );
      expect(find.text('Bea is now the owner'), findsOneWidget);
    });

    testWidgets('an admin removes members, but not admins or the owner', (
      tester,
    ) async {
      await openHub(
        tester,
        role: 'admin',
        members: [
          memberJson(userId: Ids.crisId, displayName: 'Cris', role: 'owner'),
          memberJson(role: 'admin'),
          memberJson(
            userId: '0190c3a5-0000-7000-8000-000000000004',
            displayName: 'Dan',
            role: 'admin',
          ),
          bea,
        ],
      );
      backend.adapter.on(
        'DELETE',
        ApiPaths.member(Ids.groupId, Ids.beaId),
        (_) => const FakeReply.noContent(),
      );

      expect(find.byTooltip('Actions for Cris'), findsNothing);
      expect(find.byTooltip('Actions for Dan'), findsNothing);
      expect(find.byTooltip('Actions for Ana'), findsNothing);
      await tapAndSettle(tester, find.byTooltip('Actions for Bea'));
      expect(find.text('Make admin'), findsNothing);
      expect(find.text('Transfer ownership'), findsNothing);
      await tapAndSettle(tester, find.text('Remove from group'));
      expect(find.text('Remove Bea?'), findsOneWidget);
      await tapAndSettle(tester, dialogButton('Remove'));

      expect(
        backend.adapter.requestsTo(
          'DELETE',
          ApiPaths.member(Ids.groupId, Ids.beaId),
        ),
        hasLength(1),
      );
      expect(find.text('Bea was removed'), findsOneWidget);
    });

    testWidgets('a member gets no member actions', (tester) async {
      await openHub(tester, role: 'member');

      expect(find.byTooltip('Actions for Bea'), findsNothing);
    });
  });

  testWidgets('my settings: the show_birthday switch', (tester) async {
    await openHub(tester);
    backend.adapter.onJson('PUT', ApiPaths.mySettings(Ids.groupId), {
      ...ana,
      'show_birthday': true,
    });

    await tapAndSettle(tester, find.text('Show my birthday to this group'));

    expect(
      backend.adapter
          .requestsTo('PUT', ApiPaths.mySettings(Ids.groupId))
          .single
          .jsonMap,
      {'show_birthday': true},
    );
  });

  group('invites', () {
    testWidgets('lists status and use count; revoke when can_delete', (
      tester,
    ) async {
      await openHub(
        tester,
        invites: [
          inviteJson(maxUses: 5, useCount: 2),
          inviteJson(
            id: 'i2',
            code: 'ZZZZZZZZZZ',
            status: 'revoked',
            createdById: Ids.beaId,
            createdByName: 'Bea',
          ),
          inviteJson(
            id: 'i3',
            code: 'YYYYYYYYYY',
            status: 'exhausted',
            maxUses: 1,
            useCount: 1,
            canDelete: false,
          ),
        ],
      );
      backend.adapter.on(
        'DELETE',
        ApiPaths.invite(Ids.groupId, Ids.inviteId),
        (_) => const FakeReply.noContent(),
      );

      expect(find.text('ABCDE-FGHJK'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining('2 of 5 uses'), findsOneWidget);
      expect(find.text('Revoked'), findsOneWidget);
      expect(find.textContaining('by Bea'), findsOneWidget);
      expect(find.text('Used up'), findsOneWidget);
      // Only the valid one can be shared, and only it can still be revoked
      // (the used-up one has can_delete false).
      expect(find.text('Share'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Revoke'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(TextButton, 'Revoke'));
      await tapAndSettle(tester, dialogButton('Revoke'));

      expect(
        backend.adapter.requestsTo(
          'DELETE',
          ApiPaths.invite(Ids.groupId, Ids.inviteId),
        ),
        hasLength(1),
      );
      expect(find.text('Invite revoked'), findsOneWidget);
    });

    testWidgets('share uses the invite URL; copy gives XXXXX-XXXXX', (
      tester,
    ) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await openHub(tester, invites: [inviteJson()]);

      await tapAndSettle(tester, find.text('Share'));
      const message =
          'Join "Movie night" on Friends: '
          'https://friends.example.com/join/ABCDEFGHJK';
      expect(backend.sharer.shared, [message]);

      await tapAndSettle(tester, find.text('Copy code'));
      expect(clipboard, 'ABCDE-FGHJK');
      expect(find.text('Code copied'), findsOneWidget);
    });

    testWidgets('a member creates an invite: no "never" option', (
      tester,
    ) async {
      await openHub(tester, role: 'member');
      backend.adapter.onJson(
        'POST',
        ApiPaths.invites(Ids.groupId),
        inviteJson(),
        status: 201,
      );

      await tapAndSettle(tester, find.text('Create invite'));
      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('Never'), findsNothing);
      await tapAndSettle(tester, find.text('1 day'));
      await tapAndSettle(tester, sheetButton('Create invite'));

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.invites(Ids.groupId))
            .single
            .jsonMap,
        {'max_uses': null, 'expires_in_hours': 24, 'never_expires': false},
      );
      // The new invite, ready to share.
      expect(find.text('Invite created'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('ABCDE-FGHJK'),
        ),
        findsOneWidget,
      );
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Share'),
        ),
      );
      expect(backend.sharer.shared.single, contains('/join/ABCDEFGHJK'));
    });

    testWidgets('an admin can create a never-expiring invite with max uses', (
      tester,
    ) async {
      await openHub(tester, role: 'admin');
      backend.adapter.onJson(
        'POST',
        ApiPaths.invites(Ids.groupId),
        inviteJson(expiresAt: null, maxUses: 5),
        status: 201,
      );

      await tapAndSettle(tester, find.text('Create invite'));
      await tapAndSettle(tester, find.text('Never'));
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Max uses'),
        '500',
      );
      await tapAndSettle(tester, sheetButton('Create invite'));
      expect(
        find.text('Enter a number from 1 to 100, or leave it empty.'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Max uses'),
        '5',
      );
      await tapAndSettle(tester, sheetButton('Create invite'));

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.invites(Ids.groupId))
            .single
            .jsonMap,
        {'max_uses': 5, 'expires_in_hours': 168, 'never_expires': true},
      );
    });

    testWidgets('members can only invite when the group allows it', (
      tester,
    ) async {
      await openHub(tester, role: 'member', membersCanInvite: false);

      expect(find.text('Create invite'), findsNothing);
      expect(
        find.text('Only admins can invite people to this group.'),
        findsOneWidget,
      );
      expect(find.text('You see the invites you created.'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('edit is for admin+, delete for the owner', (tester) async {
      await openHub(tester, role: 'member');
      expect(find.text('Edit group'), findsNothing);
      expect(find.text('Delete group'), findsNothing);
      expect(find.text('Leave group'), findsOneWidget);
    });

    testWidgets('Edit group opens the form', (tester) async {
      await openHub(tester, role: 'admin');
      expect(find.text('Delete group'), findsNothing);

      await tapAndSettle(tester, find.text('Edit group'));

      expect(find.byType(GroupFormScreen), findsOneWidget);
    });

    testWidgets('a member leaves after confirming', (tester) async {
      final container = await openHub(tester, role: 'member');
      backend.lastGroup.groupId = Ids.groupId;
      backend.adapter.on(
        'DELETE',
        ApiPaths.member(Ids.groupId, Ids.anaId),
        (_) => const FakeReply.noContent(),
      );

      await tapAndSettle(tester, find.text('Leave group'));
      expect(find.text('Leave Movie night?'), findsOneWidget);
      await tapAndSettle(tester, dialogButton('Leave'));

      expect(currentLocation(container), '/groups');
      expect(find.byType(GroupsListScreen), findsOneWidget);
      expect(find.text('You left Movie night'), findsOneWidget);
      expect(backend.lastGroup.groupId, isNull);
    });

    testWidgets('the owner leaving gets 409 owner_must_transfer and goes '
        'through the transfer flow', (tester) async {
      final container = await openHub(tester);
      var transferred = false;
      backend.adapter
        ..on(
          'DELETE',
          ApiPaths.member(Ids.groupId, Ids.anaId),
          (_) => transferred
              ? const FakeReply.noContent()
              : FakeReply.problem(409, ErrorCodes.ownerMustTransfer),
        )
        ..on('POST', ApiPaths.transfer(Ids.groupId), (_) {
          transferred = true;
          return FakeReply.json(groupJson(myRole: 'admin'));
        });

      await tapAndSettle(tester, find.text('Leave group'));
      expect(
        find.text("You own this group, so you'll choose a new owner first."),
        findsOneWidget,
      );
      await tapAndSettle(tester, dialogButton('Leave'));

      expect(find.byType(TransferOwnershipDialog), findsOneWidget);
      expect(find.text('Choose a new owner'), findsOneWidget);
      // Only the others are candidates.
      expect(
        find.descendant(
          of: find.byType(TransferOwnershipDialog),
          matching: find.byType(RadioListTile<String>),
        ),
        findsOneWidget,
      );
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(TransferOwnershipDialog),
          matching: find.text('Bea'),
        ),
      );
      await tapAndSettle(tester, dialogButton('Transfer and leave'));

      expect(
        backend.adapter
            .requestsTo('POST', ApiPaths.transfer(Ids.groupId))
            .single
            .jsonMap,
        {'user_id': Ids.beaId},
      );
      expect(
        backend.adapter.requestsTo(
          'DELETE',
          ApiPaths.member(Ids.groupId, Ids.anaId),
        ),
        hasLength(2),
      );
      expect(currentLocation(container), '/groups');
      expect(find.text('You left Movie night'), findsOneWidget);
    });

    testWidgets('the only member confirms that leaving deletes the group', (
      tester,
    ) async {
      final container = await openHub(tester, members: [ana]);
      backend.adapter.on(
        'DELETE',
        ApiPaths.member(Ids.groupId, Ids.anaId),
        (_) => const FakeReply.noContent(),
      );

      await tapAndSettle(tester, find.text('Leave group'));
      expect(find.text('Leave and delete Movie night?'), findsOneWidget);
      await tapAndSettle(tester, dialogButton('Leave and delete'));

      expect(currentLocation(container), '/groups');
      expect(find.text('Movie night was deleted'), findsOneWidget);
    });

    testWidgets('the owner deletes the group after confirming', (tester) async {
      final container = await openHub(tester);
      backend.adapter.on(
        'DELETE',
        ApiPaths.group(Ids.groupId),
        (_) => const FakeReply.noContent(),
      );

      await tapAndSettle(tester, find.text('Delete group'));
      expect(find.text('Delete Movie night?'), findsOneWidget);
      await tapAndSettle(tester, find.text('Cancel'));
      expect(
        backend.adapter.requestsTo('DELETE', ApiPaths.group(Ids.groupId)),
        isEmpty,
      );

      await tapAndSettle(tester, find.text('Delete group'));
      await tapAndSettle(tester, dialogButton('Delete group'));

      expect(
        backend.adapter.requestsTo('DELETE', ApiPaths.group(Ids.groupId)),
        hasLength(1),
      );
      expect(currentLocation(container), '/groups');
      expect(find.text('Movie night was deleted'), findsOneWidget);
    });

    testWidgets('a 403 explains, and reloads the group', (tester) async {
      await openHub(tester);
      backend.adapter.onProblem(
        'PUT',
        ApiPaths.role(Ids.groupId, Ids.beaId),
        403,
        ErrorCodes.forbidden,
      );
      final before = backend.adapter
          .requestsTo('GET', ApiPaths.group(Ids.groupId))
          .length;

      await tapAndSettle(tester, find.byTooltip('Actions for Bea'));
      await tapAndSettle(tester, find.text('Make admin'));

      expect(
        find.text("You don't have permission to do that any more."),
        findsOneWidget,
      );
      expect(
        backend.adapter.requestsTo('GET', ApiPaths.group(Ids.groupId)).length,
        before + 1,
      );
    });
  });
}
