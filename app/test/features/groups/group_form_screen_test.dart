import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/error_codes.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/groups/presentation/group_form_screen.dart';
import 'package:friends/features/groups/presentation/group_hub_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(
        find.descendant(of: field(label), matching: find.byType(TextField)),
      )
      .controller!
      .text;

  Future<ProviderContainer> open(WidgetTester tester, String location) {
    tester.view
      ..physicalSize = const Size(800, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: location,
    );
  }

  List<Map<String, Object?>> bodies(String method, String path) => [
    for (final request in backend.adapter.requestsTo(method, path))
      request.jsonMap,
  ];

  group('create', () {
    testWidgets('validates the fields before sending anything', (tester) async {
      await open(tester, Routes.newGroup);

      await tester.enterText(field('Name'), '   ');
      await tester.enterText(field('Emoji'), 'x' * 17);
      await tester.enterText(field('Description'), 'y' * 501);
      await tester.enterText(field('Currency'), 'EURO');
      await tester.enterText(field('Timezone'), ' ');
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(find.text('Use at most 16 characters.'), findsOneWidget);
      expect(find.text('Use at most 500 characters.'), findsOneWidget);
      expect(
        find.text('Use a 3-letter currency code, e.g. EUR.'),
        findsOneWidget,
      );
      expect(find.text('Enter a timezone.'), findsOneWidget);

      await tester.enterText(field('Name'), 'n' * 61);
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(find.text('Use at most 60 characters.'), findsOneWidget);

      expect(bodies('POST', ApiPaths.groups), isEmpty);
    });

    testWidgets('defaults: EUR, the device timezone, the first colour, '
        'default categories on', (tester) async {
      backend
        ..stubGroup(group: groupJson(myRole: 'owner'))
        ..adapter.onJson(
          'POST',
          ApiPaths.groups,
          groupJson(myRole: 'owner'),
          status: 201,
        );
      final container = await open(tester, Routes.newGroup);

      expect(fieldText(tester, 'Currency'), 'EUR');
      expect(fieldText(tester, 'Timezone'), 'Europe/Bucharest');
      expect(find.text('Members can invite'), findsNothing);

      await tester.enterText(field('Name'), '  Movie night ');
      await tester.enterText(field('Emoji'), '🎬');
      await tester.enterText(field('Currency'), 'ron');
      await tester.tap(find.byTooltip('Blue'));
      await tester.tap(find.text('Add default categories'));
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();

      expect(bodies('POST', ApiPaths.groups).single, {
        'name': 'Movie night',
        'currency': 'RON',
        'members_can_invite': true,
        'seed_default_categories': false,
        'description': null,
        'emoji': '🎬',
        'color': '#1E88E5',
        'timezone': 'Europe/Bucharest',
      });
      expect(currentLocation(container), '/groups/${Ids.groupId}/backlog');
    });

    testWidgets('offers 8 preset colours', (tester) async {
      await open(tester, Routes.newGroup);

      for (final name in [
        'Coral',
        'Red',
        'Amber',
        'Green',
        'Teal',
        'Blue',
        'Purple',
        'Pink',
      ]) {
        expect(find.byTooltip(name), findsOneWidget);
      }
    });

    testWidgets('shows server errors on their fields, the rest above', (
      tester,
    ) async {
      backend.adapter.onProblem(
        'POST',
        ApiPaths.groups,
        422,
        ErrorCodes.validationError,
        errors: [
          {
            'field': 'timezone',
            'message': 'Unknown timezone.',
            'type': 'value_error',
          },
        ],
      );
      await open(tester, Routes.newGroup);

      await tester.enterText(field('Name'), 'Movie night');
      await tester.enterText(field('Timezone'), 'Mars/Olympus');
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(find.text('Unknown timezone.'), findsOneWidget);

      backend.adapter.onProblem(
        'POST',
        ApiPaths.groups,
        422,
        ErrorCodes.limitReached,
      );
      await tester.enterText(field('Timezone'), 'Europe/Paris');
      await tester.pump(); // rebuild without the server error before submitting
      await tester.ensureVisible(find.text('Create group'));
      await tester.tap(find.text('Create group'));
      await tester.pumpAndSettle();
      expect(
        find.text("You're in 50 groups already, the most allowed."),
        findsOneWidget,
      );
    });
  });

  group('edit', () {
    testWidgets('sends the complete settings, members_can_invite included', (
      tester,
    ) async {
      backend
        ..stubGroup(
          group: groupJson(myRole: 'admin', description: 'Fridays'),
        )
        ..adapter.onJson(
          'PUT',
          ApiPaths.group(Ids.groupId),
          groupJson(myRole: 'admin', name: 'Film club'),
        );
      final container = await open(tester, Routes.editGroup(Ids.groupId));

      expect(fieldText(tester, 'Name'), 'Movie night');
      expect(fieldText(tester, 'Description'), 'Fridays');
      expect(find.text('Add default categories'), findsNothing);

      await tester.enterText(field('Name'), 'Film club');
      await tester.enterText(field('Description'), '');
      await tester.tap(find.text('Members can invite'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(bodies('PUT', ApiPaths.group(Ids.groupId)).single, {
        'name': 'Film club',
        'currency': 'EUR',
        'timezone': 'Europe/Bucharest',
        'members_can_invite': false,
        'description': null,
        'emoji': '🎬',
        'color': '#1E88E5',
      });
      // Opened directly: nothing to pop, so it goes to the group hub.
      expect(currentLocation(container), '/groups/${Ids.groupId}/group');
      expect(find.byType(GroupHubScreen), findsOneWidget);
      expect(find.text('Group saved'), findsOneWidget);
    });

    testWidgets('keeps a colour that is not a preset', (tester) async {
      backend.stubGroup(
        group: groupJson(myRole: 'owner', color: '#123456'),
      );
      await open(tester, Routes.editGroup(Ids.groupId));

      expect(find.byTooltip('Current colour'), findsOneWidget);
    });

    testWidgets('members only get an explanation', (tester) async {
      backend.stubGroup();
      await open(tester, Routes.editGroup(Ids.groupId));

      expect(find.text('Only admins can edit this group.'), findsOneWidget);
      expect(find.byType(GroupForm), findsNothing);
    });

    testWidgets('a group I am not in is not found', (tester) async {
      await open(tester, Routes.editGroup(Ids.groupId));

      expect(find.text('Group not found'), findsOneWidget);
    });
  });
}
