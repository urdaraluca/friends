import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/feed/domain/feed_text.dart';
import 'package:friends/features/feed/presentation/feed_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/fake_http_adapter.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

FeedItem _item({
  String action = 'activity.created',
  String? subjectType = 'activity',
  String? subjectTitle = 'Picnic',
  bool subjectExists = true,
  Map<String, Object?> data = const {},
  Map<String, Object?>? actor,
}) => FeedItem.fromJson(
  feedItemJson(
    action: action,
    subjectType: subjectType,
    subjectTitle: subjectTitle,
    subjectExists: subjectExists,
    data: data,
    actor: actor,
  ),
);

String _sentence(FeedItem item) =>
    feedSentence(item).map((span) => span.text).join();

void main() {
  group('feed text', () {
    test('sentences name the actor and the subject', () {
      expect(_sentence(_item()), 'Ana added Picnic');
      expect(
        _sentence(
          _item(action: 'activity.status_changed', data: {'to': 'done'}),
        ),
        'Ana marked Picnic as done',
      );
      expect(
        _sentence(
          _item(action: 'activity.status_changed', data: {'to': 'planning'}),
        ),
        'Ana moved Picnic to Planning',
      );
      expect(
        _sentence(
          _item(
            action: 'poll.created',
            subjectType: 'poll',
            subjectTitle: 'Which film?',
          ),
        ),
        'Ana asked “Which film?”',
      );
      expect(
        _sentence(
          _item(
            action: 'member.role_changed',
            subjectType: 'member',
            subjectTitle: 'Bea',
            data: {'to': 'admin'},
          ),
        ),
        'Ana made Bea an admin',
      );
      expect(
        _sentence(
          _item(
            action: 'member.joined',
            subjectType: 'member',
            subjectTitle: 'Bea',
          ),
        ),
        'Bea joined the group',
      );
      expect(
        _sentence(_item(action: 'wheel.accepted', subjectType: 'spin')),
        "Ana said let's do Picnic",
      );
      // A deleted account.
      final item = FeedItem.fromJson({...feedItemJson(), 'actor': null});
      expect(_sentence(item), 'Someone added Picnic');
      // The names are bold.
      expect(
        feedSentence(_item()).where((span) => span.bold).map((s) => s.text),
        ['Ana', 'Picnic'],
      );
    });

    test('targets open what still exists', () {
      const gid = Ids.groupId;
      expect(feedTarget(gid, _item()), Routes.activity(gid, Ids.activityId));
      expect(feedTarget(gid, _item(subjectExists: false)), isNull);
      expect(
        feedTarget(
          gid,
          _item(
            action: 'poll.voted',
            subjectType: 'poll',
            data: {'activity_id': Ids.otherActivityId},
          ),
        ),
        Routes.activity(gid, Ids.otherActivityId),
      );
      expect(
        feedTarget(gid, _item(action: 'wheel.spun', subjectType: 'spin')),
        Routes.wheelHistory(gid),
      );
      expect(
        feedTarget(gid, _item(action: 'event.created', subjectType: 'event')),
        Routes.event(gid, Ids.activityId),
      );
    });

    test('times are relative while recent', () {
      final now = DateTime(2026, 10, 15, 12);
      expect(
        feedTime(now.subtract(const Duration(seconds: 20)), now),
        'just now',
      );
      expect(
        feedTime(now.subtract(const Duration(minutes: 5)), now),
        '5 min ago',
      );
      expect(feedTime(now.subtract(const Duration(hours: 3)), now), '3 h ago');
      expect(feedTime(DateTime(2026, 10, 14, 20, 30), now), 'yesterday, 20:30');
      expect(feedTime(DateTime(2026, 10, 2, 9), now), 'Fri 2 Oct');
      expect(feedTime(DateTime(2025, 12, 31, 9), now), '31 Dec 2025');
    });
  });

  group('FeedScreen', () {
    late TestBackend backend;

    setUp(() {
      backend = TestBackend()..stubGroup();
    });

    testWidgets('lists the feed, pages it and opens an item', (tester) async {
      backend.adapter.on('GET', ApiPaths.feed(Ids.groupId), (request) {
        final cursor = request.options.queryParameters['cursor'];
        return FakeReply.json({
          'items': cursor == null
              ? [
                  feedItemJson(),
                  feedItemJson(
                    id: '0190c3a5-0000-7000-8000-0000000000fa',
                    action: 'activity.deleted',
                    subjectTitle: 'Karaoke',
                    subjectExists: false,
                  ),
                ]
              : [
                  feedItemJson(
                    id: '0190c3a5-0000-7000-8000-0000000000fb',
                    action: 'group.created',
                    subjectType: 'group',
                    subjectId: Ids.groupId,
                    subjectTitle: 'Movie night',
                  ),
                ],
          'next_cursor': cursor == null ? 'page-2' : null,
        });
      });
      final container = await tester.pumpFriendsApp(
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
        location: Routes.groupFeed(Ids.groupId),
      );

      expect(find.byType(FeedTile), findsNWidgets(3));
      expect(find.text('Ana added Picnic', findRichText: true), findsOneWidget);
      expect(
        find.text('Ana deleted Karaoke', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('Ana created the group', findRichText: true),
        findsOneWidget,
      );
      final requests = backend.adapter.requestsTo(
        'GET',
        ApiPaths.feed(Ids.groupId),
      );
      expect(requests.last.options.queryParameters['cursor'], 'page-2');

      // A deleted subject can't be opened.
      final deleted = tester.widget<ListTile>(
        find.descendant(
          of: find.byType(FeedTile).at(1),
          matching: find.byType(ListTile),
        ),
      );
      expect(deleted.onTap, isNull);

      await tester.tap(find.text('Ana added Picnic', findRichText: true));
      await tester.pumpAndSettle();
      expect(
        currentLocation(container),
        Routes.activity(Ids.groupId, Ids.activityId),
      );
    });
  });
}
