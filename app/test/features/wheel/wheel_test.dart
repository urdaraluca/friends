import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/wheel/domain/wheel_math.dart';
import 'package:friends/features/wheel/presentation/fortune_wheel.dart';
import 'package:friends/features/wheel/presentation/wheel_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  group('WheelMath', () {
    test('always stops on the chosen slice (n = 2..50, 1000 jitters)', () {
      final random = Random(42);
      for (var count = 2; count <= 50; count++) {
        for (var run = 0; run < 1000; run++) {
          final index = random.nextInt(count);
          final jitter = (random.nextDouble() * 2 - 1) * WheelMath.maxJitter;
          final current = (random.nextDouble() - 0.5) * 40;
          final turns =
              WheelMath.minTurns +
              random.nextInt(WheelMath.maxTurns - WheelMath.minTurns + 1);
          final target = WheelMath.targetRotation(
            current: current,
            index: index,
            count: count,
            turns: turns,
            jitter: jitter,
          );

          expect(
            WheelMath.sliceAtPointer(target, count),
            index,
            reason: 'n=$count i=$index jitter=$jitter current=$current',
          );
          final extra = target - current;
          expect(extra, greaterThanOrEqualTo(turns * WheelMath.fullTurn));
          expect(extra, lessThan((turns + 1) * WheelMath.fullTurn));
        }
      }
    });

    test('slice 0 starts at 12 o clock and goes clockwise', () {
      // Unturned, the pointer is on the boundary between the last slice and
      // slice 0; a tiny clockwise turn shows the last slice.
      expect(WheelMath.sliceAtPointer(-0.01, 4), 0);
      expect(WheelMath.sliceAtPointer(0.01, 4), 3);
    });

    test('spinShape is deterministic and within bounds', () {
      final a = WheelMath.spinShape(7);
      expect(WheelMath.spinShape(7), a);
      for (var seed = 0; seed < 200; seed++) {
        final shape = WheelMath.spinShape(seed);
        expect(shape.turns, inInclusiveRange(5, 7));
        expect(shape.jitter.abs(), lessThanOrEqualTo(WheelMath.maxJitter));
      }
    });
  });

  group('WheelScreen', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend()
        ..stubGroup()
        ..stubBacklog(categories: categoryTreeJson());
    });

    Future<ProviderContainer> openWheel(
      WidgetTester tester, {
      bool disableAnimations = true,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: disableAnimations);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      return await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.groupTab(Ids.groupId, GroupTab.wheel),
      );
    }

    void stubCandidates(List<Map<String, Object?>> items, {int? total}) =>
        backend.adapter.onJson(
          'GET',
          ApiPaths.wheelCandidates(Ids.groupId),
          wheelCandidatesJson(items, total: total),
        );

    final two = [
      activitySummaryJson(),
      activitySummaryJson(
        id: Ids.otherActivityId,
        title: 'Catan',
        categoryId: Ids.gamesCategoryId,
      ),
    ];

    testWidgets('by default only ideas I am interested in (interested_by)', (
      tester,
    ) async {
      stubCandidates(two);

      await openWheel(tester);

      final query = backend.adapter
          .requestsTo('GET', ApiPaths.wheelCandidates(Ids.groupId))
          .last
          .queryParametersAll;
      expect(query['interested_by'], [Ids.anaId]);
      expect(query['status'], ['idea', 'planning']);
      expect(find.byType(FortuneWheel), findsOneWidget);
      expect(find.text('2 ideas'), findsOneWidget);
    });

    testWidgets('Spin is disabled below 2 candidates', (tester) async {
      stubCandidates([activitySummaryJson()]);

      await openWheel(tester);

      final spin = find.widgetWithText(FilledButton, 'Spin!');
      expect(tester.widget<FilledButton>(spin).onPressed, isNull);
      expect(find.text('Add at least 2 ideas to spin'), findsOneWidget);
    });

    testWidgets('with animations off the result shows at once', (tester) async {
      stubCandidates(two);
      backend.adapter.onJson(
        'POST',
        ApiPaths.spins(Ids.groupId),
        wheelSpinJson(),
        status: 201,
      );
      await openWheel(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Spin!'));
      // A few short frames for the request, far less than the 4.5 s spin.
      for (var frame = 0; frame < 5; frame++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(SpinResultCard), findsOneWidget);
      expect(find.text('Catan'), findsWidgets);
      final body = backend.adapter
          .requestsTo('POST', ApiPaths.spins(Ids.groupId))
          .single
          .jsonMap;
      expect(body['activity_ids'], isNull); // the whole filtered pool
      expect(
        (body['filters']! as Map<String, Object?>)['interested_by'],
        Ids.anaId,
      );
    });

    testWidgets('unchecking candidates sends the hand-picked activity_ids', (
      tester,
    ) async {
      stubCandidates([...two, activitySummaryJson(id: 'third', title: 'Heat')]);
      backend.adapter.onJson(
        'POST',
        ApiPaths.spins(Ids.groupId),
        wheelSpinJson(),
        status: 201,
      );
      await openWheel(tester);

      await tester.tap(find.text('3 ideas'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Heat'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Spin!'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.spins(Ids.groupId))
          .single
          .jsonMap;
      expect(body['activity_ids'], [Ids.activityId, Ids.otherActivityId]);
    });

    testWidgets("Let's do it! accepts the spin", (tester) async {
      stubCandidates(two);
      backend.adapter
        ..onJson(
          'POST',
          ApiPaths.spins(Ids.groupId),
          wheelSpinJson(),
          status: 201,
        )
        ..onJson(
          'POST',
          ApiPaths.acceptSpin('spin-1'),
          wheelSpinJson(
            acceptedAt: '2026-09-26T18:01:00Z',
            acceptedBy: userPublicJson(),
          ),
        );
      await openWheel(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Spin!'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Let's do it!"));
      await tester.pumpAndSettle();

      expect(
        backend.adapter.requestsTo('POST', ApiPaths.acceptSpin('spin-1')),
        hasLength(1),
      );
      expect(find.text("You said let's do it."), findsOneWidget);
      expect(find.text("Let's do it!"), findsNothing);
    });

    testWidgets('409 result_deleted is explained', (tester) async {
      stubCandidates(two);
      backend.adapter
        ..onJson(
          'POST',
          ApiPaths.spins(Ids.groupId),
          wheelSpinJson(),
          status: 201,
        )
        ..onProblem(
          'POST',
          ApiPaths.acceptSpin('spin-1'),
          409,
          'result_deleted',
        );
      await openWheel(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Spin!'));
      await tester.pumpAndSettle();

      await tester.tap(find.text("Let's do it!"));
      await tester.pumpAndSettle();

      expect(
        find.text('That idea was deleted in the meantime.'),
        findsOneWidget,
      );
    });

    testWidgets('the wheel animates to the result when animations are on', (
      tester,
    ) async {
      stubCandidates(two);
      backend.adapter.onJson(
        'POST',
        ApiPaths.spins(Ids.groupId),
        wheelSpinJson(),
        status: 201,
      );
      await openWheel(tester, disableAnimations: false);

      await tester.tap(find.widgetWithText(FilledButton, 'Spin!'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SpinResultCard), findsNothing); // still spinning
      await tester.pump(FortuneWheel.spinDuration);
      await tester.pumpAndSettle();
      expect(find.byType(SpinResultCard), findsOneWidget);
    });
  });
}
