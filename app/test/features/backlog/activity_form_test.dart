import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/presentation/widgets/dynamic_fields_form.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

FieldDef field(String key, String type, {List<String>? options}) =>
    FieldDef.fromJson({
      'key': key,
      'label': 'Label $key',
      'type': type,
      'options': options,
      'min': null,
      'max': null,
      'show_on_card': false,
    });

void main() {
  group('DynamicFieldsForm', () {
    testWidgets('renders an input for each type and shows server errors', (
      tester,
    ) async {
      final defs = [
        field('t', 'text'),
        field('lt', 'long_text'),
        field('n', 'number'),
        field('r', 'rating'),
        field('u', 'url'),
        field('s', 'select', options: ['A', 'B']),
        field('y', 'year'),
      ];
      final changes = <String, String>{};
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpApp(
        Scaffold(
          body: SingleChildScrollView(
            child: DynamicFieldsForm(
              fieldDefs: defs,
              values: const {'r': '8.1', 'y': '1999'},
              onChanged: (key, text) => changes[key] = text,
              serverError: (key) => key == 'y' ? 'Between 1800 and 2200' : null,
            ),
          ),
        ),
      );

      for (final def in defs) {
        expect(find.text(def.label), findsOneWidget, reason: def.key);
      }
      // Rating: a slider with the value; the choice: a dropdown.
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('8.1'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      // The server's error on its field.
      expect(find.text('Between 1800 and 2200'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Label n'),
        '42',
      );
      await tester.tap(find.byTooltip('Clear Label r'));
      expect(changes, {'n': '42', 'r': ''});
    });

    testWidgets('an empty rating offers "Rate it"', (tester) async {
      String? rated;
      await tester.pumpApp(
        Scaffold(
          body: DynamicFieldsForm(
            fieldDefs: [field('r', 'rating')],
            values: const {},
            onChanged: (_, text) => rated = text,
          ),
        ),
      );

      await tester.tap(find.text('Rate it'));
      expect(rated, '5');
    });
  });

  group('ActivityForm', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
    });

    Future<ProviderContainer> open(WidgetTester tester, String location) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
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

    Future<void> pickCategory(WidgetTester tester, String name) async {
      await tester.tap(find.text('Uncategorised').hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('create sends every field, with the custom fields', (
      tester,
    ) async {
      backend.adapter.onJson(
        'POST',
        ApiPaths.activities(Ids.groupId),
        activityJson(),
        status: 201,
      );
      backend.adapter.onJson(
        'GET',
        ApiPaths.activity(Ids.activityId),
        activityJson(),
      );
      await open(tester, Routes.newActivity(Ids.groupId));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Dune',
      );
      await pickCategory(tester, 'Movie night');
      expect(find.text('IMDb rating'), findsOneWidget);
      await tester.tap(find.text('Rate it'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Year'),
        '2021',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Estimated cost'),
        '12',
      );
      await tester.tap(find.text('Add idea'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.activities(Ids.groupId))
          .single
          .jsonMap;
      expect(body['title'], 'Dune');
      expect(body['category_id'], Ids.movieCategoryId);
      expect(body['status'], 'idea');
      expect(body['estimated_cost'], 12);
      expect(body['attributes'], {'imdb_rating': 5, 'year': 2021});
      // Explicit nulls (contract 1.4): the body is the complete state.
      expect(body.containsKey('due_date'), isTrue);
      expect(body['due_date'], isNull);
      expect(body['owner_id'], isNull);
      // Then the new activity opens.
      expect(find.text('Dune'), findsWidgets);
    });

    testWidgets('changing the category warns about fields it would drop', (
      tester,
    ) async {
      backend.adapter.onJson(
        'GET',
        ApiPaths.activity(Ids.activityId),
        activityJson(attributes: {'imdb_rating': 8.1}),
      );
      await open(tester, Routes.editActivity(Ids.groupId, Ids.activityId));
      expect(find.text('8.1'), findsOneWidget);

      await tester.tap(find.text('Movie night').hitTestable().first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Games').last);
      await tester.pumpAndSettle();

      expect(find.text('Change the category?'), findsOneWidget);
      expect(find.textContaining('IMDb rating'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('8.1'), findsOneWidget); // unchanged
    });

    testWidgets('a 409 version_conflict offers Reload only, then reloads', (
      tester,
    ) async {
      var version = 1;
      backend.adapter
        ..on(
          'GET',
          ApiPaths.activity(Ids.activityId),
          (_) => FakeReply.json(activityJson(version: version)),
        )
        ..onProblem(
          'PUT',
          ApiPaths.activity(Ids.activityId),
          409,
          'version_conflict',
        );
      await open(tester, Routes.editActivity(Ids.groupId, Ids.activityId));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Dune: Part Two',
      );
      await tester.pump();
      version = 2;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Someone else saved first'), findsOneWidget);
      expect(find.text('Overwrite'), findsNothing);
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();

      // The form starts over from the server's version 2.
      expect(find.widgetWithText(TextFormField, 'Dune'), findsOneWidget);
      final gets = backend.adapter.requestsTo(
        'GET',
        ApiPaths.activity(Ids.activityId),
      );
      expect(gets.length, greaterThanOrEqualTo(2));
      final put = backend.adapter
          .requestsTo('PUT', ApiPaths.activity(Ids.activityId))
          .single
          .jsonMap;
      expect(put['version'], 1);
    });

    testWidgets('server field errors land on their fields', (tester) async {
      backend.adapter
        ..onJson('GET', ApiPaths.activity(Ids.activityId), activityJson())
        ..onProblem(
          'PUT',
          ApiPaths.activity(Ids.activityId),
          422,
          'invalid_attributes',
          errors: [
            {
              'field': 'attributes.imdb_rating',
              'message': 'At most one decimal.',
              'type': 'too_many_decimals',
            },
          ],
        );
      await open(tester, Routes.editActivity(Ids.groupId, Ids.activityId));

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('At most one decimal.'), findsOneWidget);
    });
  });
}
