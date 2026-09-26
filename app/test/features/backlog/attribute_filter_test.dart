import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/activity_filter.dart';
import 'package:friends/features/backlog/presentation/widgets/attribute_filter.dart';
import 'package:friends/features/wheel/data/wheel_providers.dart';
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
      ..stubBacklog(categories: categoryTreeJson());
  });

  Future<ProviderContainer> open(WidgetTester tester, String location) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1400));
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

  test('labels and query values', () {
    const rating = AttributeFilter(
      key: 'imdb_rating',
      op: AttributeOp.gte,
      value: '7.5',
    );
    final defs = [
      for (final json in movieFieldDefsJson()) FieldDef.fromJson(json),
    ];
    expect(attrParam(rating), 'imdb_rating:gte:7.5');
    expect(attributeFilterLabel(rating, defs), 'IMDb rating ≥ 7.5');
    expect(
      attributeFilterLabel(
        const AttributeFilter(
          key: 'genre',
          op: AttributeOp.eq,
          value: 'Comedy',
        ),
        defs,
      ),
      'Genre: Comedy',
    );
    // A link can't be filtered on.
    expect(defs.where(isFilterable).map((d) => d.key), [
      'genre',
      'imdb_rating',
      'year',
      'runtime_min',
    ]);
  });

  testWidgets('the backlog filters on the category fields', (tester) async {
    final container = await open(tester, Routes.groupBacklog(Ids.groupId));
    // No category: no Fields chip.
    expect(find.widgetWithText(InputChip, 'Fields'), findsNothing);

    container
        .read(backlogFilterProvider(Ids.groupId).notifier)
        .set(const ActivityFilter(categoryId: Ids.movieCategoryId));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InputChip, 'Fields'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'IMDb rating at least'),
      '7,5',
    );
    await tester.tap(find.text('Any').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comedy').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final query = backend.adapter
        .requestsTo('GET', ApiPaths.activities(Ids.groupId))
        .last
        .queryParametersAll;
    expect(query['attr'], ['genre:eq:Comedy', 'imdb_rating:gte:7.5']);
    expect(
      find.widgetWithText(InputChip, 'Genre: Comedy · IMDb rating ≥ 7.5'),
      findsOneWidget,
    );

    // Clearing the category clears its field filters.
    container
        .read(backlogFilterProvider(Ids.groupId).notifier)
        .set(const ActivityFilter());
    await tester.pumpAndSettle();
    expect(
      backend.adapter
          .requestsTo('GET', ApiPaths.activities(Ids.groupId))
          .last
          .queryParametersAll['attr'],
      isNull,
    );
  });

  testWidgets('a number is needed for a range', (tester) async {
    final container = await open(tester, Routes.groupBacklog(Ids.groupId));
    container
        .read(backlogFilterProvider(Ids.groupId).notifier)
        .set(const ActivityFilter(categoryId: Ids.movieCategoryId));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InputChip, 'Fields'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'at most').first,
      '-',
    );
    await tester.tap(find.text('Apply'));
    await tester.pump();

    expect(find.text('IMDb rating: enter a number.'), findsOneWidget);
  });

  testWidgets('the wheel sends its field filters', (tester) async {
    backend.adapter.onJson('GET', ApiPaths.wheelCandidates(Ids.groupId), {
      'items': <Object?>[],
      'total': 0,
    });
    final container = await open(
      tester,
      Routes.groupTab(Ids.groupId, GroupTab.wheel),
    );
    container
        .read(wheelFilterProvider(Ids.groupId).notifier)
        .set(
          container
              .read(wheelFilterProvider(Ids.groupId))
              .copyWith(categoryId: Ids.movieCategoryId),
        );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(InputChip, 'Fields'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Year at least'),
      '1990',
    );
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    final query = backend.adapter
        .requestsTo('GET', ApiPaths.wheelCandidates(Ids.groupId))
        .last
        .queryParametersAll;
    expect(query['attr'], ['year:gte:1990']);
    expect(container.read(wheelFilterProvider(Ids.groupId)).attributes, [
      const AttributeFilter(key: 'year', op: AttributeOp.gte, value: '1990'),
    ]);
  });
}
