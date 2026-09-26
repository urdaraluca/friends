import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/presentation/category_order_page.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

const _tripsId = '0190c3a5-0000-7000-8000-0000000000d3';
const _horrorId = '0190c3a5-0000-7000-8000-0000000000d4';
const _comedyId = '0190c3a5-0000-7000-8000-0000000000d5';

String _orderPath(String groupId) => '${ApiPaths.categories(groupId)}/order';

void main() {
  late TestBackend backend;

  List<Map<String, Object?>> tree() => [
    categoryNodeJson(
      subcategories: [
        for (final (id, name) in [(_horrorId, 'Horror'), (_comedyId, 'Comedy')])
          categoryJson(
            id: id,
            parentId: Ids.movieCategoryId,
            name: name,
            color: null,
            effectiveColor: '#7E57C2',
          ),
      ],
    ),
    categoryNodeJson(id: Ids.gamesCategoryId, name: 'Games', icon: 'games'),
    categoryNodeJson(id: _tripsId, name: 'Trips', icon: 'trips'),
  ];

  Future<ProviderContainer> open(WidgetTester tester, {String role = 'admin'}) {
    backend = TestBackend()
      ..stubGroup(group: groupJson(myRole: role))
      ..stubBacklog(categories: tree());
    backend.adapter.onJson('PUT', _orderPath(Ids.groupId), tree());
    return tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.groupCategories(Ids.groupId),
    );
  }

  Future<void> dragAbove(WidgetTester tester, String id, String aboveId) async {
    final from = tester.getCenter(find.byKey(ValueKey('drag-$id')));
    final to = tester.getTopLeft(find.byKey(ValueKey('drag-$aboveId')));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 100));
    for (var step = 1; step <= 10; step++) {
      await gesture.moveTo(
        Offset(from.dx, from.dy + (to.dy - 20 - from.dy) * step / 10),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('admins drag top-level categories into a new order', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Reorder'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryOrderPage), findsOneWidget);
    final save = find.widgetWithText(TextButton, 'Save');
    expect(tester.widget<TextButton>(save).onPressed, isNull);

    await dragAbove(tester, _tripsId, Ids.movieCategoryId);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final body = backend.adapter
        .requestsTo('PUT', _orderPath(Ids.groupId))
        .single
        .jsonMap;
    expect(body, {
      'parent_id': null,
      'category_ids': [_tripsId, Ids.movieCategoryId, Ids.gamesCategoryId],
    });
    expect(find.byType(CategoryOrderPage), findsNothing);
  });

  testWidgets('subcategories are ordered under their parent', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Reorder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reorder Movie night'));
    await tester.pumpAndSettle();
    expect(find.text('Horror'), findsOneWidget);

    await dragAbove(tester, _comedyId, _horrorId);
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    final body = backend.adapter
        .requestsTo('PUT', _orderPath(Ids.groupId))
        .single
        .jsonMap;
    expect(body, {
      'parent_id': Ids.movieCategoryId,
      'category_ids': [_comedyId, _horrorId],
    });
  });

  testWidgets('members get no Reorder button', (tester) async {
    await open(tester, role: 'member');

    expect(find.byTooltip('Reorder'), findsNothing);
  });
}
