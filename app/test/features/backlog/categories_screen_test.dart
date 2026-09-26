import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() {
    backend = TestBackend()
      ..stubGroup()
      ..stubBacklog(
        categories: [
          categoryNodeJson(
            fieldDefs: movieFieldDefsJson(),
            subcategories: [
              categoryJson(
                id: 'horror',
                parentId: Ids.movieCategoryId,
                name: 'Horror',
                color: null,
                effectiveColor: '#7E57C2',
              ),
            ],
          ),
          categoryNodeJson(
            id: Ids.gamesCategoryId,
            name: 'Games',
            icon: 'games',
            canEdit: false,
          ),
        ],
      );
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    return await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.groupCategories(Ids.groupId),
    );
  }

  testWidgets('lists the tree; edit and delete only where allowed', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Movie night'), findsOneWidget);
    expect(find.text('1 subcategory · 5 fields'), findsOneWidget);
    expect(find.byTooltip('Options for Movie night'), findsOneWidget);
    expect(find.byTooltip('Options for Games'), findsNothing);

    await tester.tap(find.text('Movie night'));
    await tester.pumpAndSettle();
    expect(find.text('Horror'), findsOneWidget);
    expect(find.text('Add a subcategory to Movie night'), findsOneWidget);
  });

  testWidgets('deleting a top-level category spells out the consequences', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.byTooltip('Options for Movie night'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Its subcategories are deleted too, and all their ideas and plans '
        'become uncategorised.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('deleting a subcategory says its ideas move to the parent', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Movie night'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Options for Horror'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.text('Its ideas and plans move to "Movie night".'),
      findsOneWidget,
    );
  });

  testWidgets('existing fields keep their key and type', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Options for Movie night'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Movie night'), findsOneWidget);
    expect(find.text('Stored values use this key, so it stays'), findsWidgets);
    expect(
      find.text('To change the type, remove the field and add it again'),
      findsWidgets,
    );
  });

  testWidgets('a new field gets its key from the label; conflicts show', (
    tester,
  ) async {
    backend.adapter.onProblem(
      'POST',
      ApiPaths.categories(Ids.groupId),
      422,
      'field_key_conflict',
      errors: [
        {
          'field': 'field_defs.0.key',
          'message':
              'The parent category or a subcategory already uses this key.',
          'type': 'field_key_conflict',
        },
      ],
    );
    await open(tester);
    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Food');
    await tester.tap(find.text('Add a field'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Label'),
      'Price range',
    );
    await tester.pump();
    expect(find.widgetWithText(TextFormField, 'price_range'), findsOneWidget);

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final body = backend.adapter
        .requestsTo('POST', ApiPaths.categories(Ids.groupId))
        .single
        .jsonMap;
    expect(body['name'], 'Food');
    expect(body['color'], '#7E57C2');
    expect(body['field_defs'], [
      {
        'key': 'price_range',
        'label': 'Price range',
        'type': 'text',
        'show_on_card': false,
        'options': null,
        'min': null,
        'max': null,
      },
    ]);
    expect(
      find.text('The parent category or a subcategory already uses this key.'),
      findsOneWidget,
    );
  });
}
