import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/features/backlog/presentation/widgets/activity_card.dart';
import 'package:friends/features/polls/data/polls_providers.dart';
import 'package:friends/features/polls/presentation/poll_card.dart';
import 'package:friends/features/polls/presentation/poll_dialogs.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/api_fixtures.dart';
import '../../helpers/fake_auth_controller.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/test_backend.dart';

void main() {
  late TestBackend backend;

  setUp(() => backend = TestBackend());

  /// A PollCard for [poll] on a real network stack; the list provider is
  /// seeded through its endpoint.
  Future<void> pumpCard(WidgetTester tester, Map<String, Object?> poll) async {
    backend.adapter.onJson('GET', ApiPaths.polls(Ids.activityId), [poll]);
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpApp(
      Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            final polls = ref.watch(pollsProvider(Ids.activityId)).value;
            if (polls == null) return const SizedBox();
            return ListView(children: [PollCard(poll: polls.single)]);
          },
        ),
      ),
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
    );
    await tester.pumpAndSettle();
  }

  List<Object?> votesSent() => [
    for (final request in backend.adapter.requestsTo(
      'PUT',
      ApiPaths.myVote(Ids.pollId),
    ))
      request.jsonMap['option_ids'],
  ];

  group('PollCard', () {
    testWidgets('single choice: tapping an option votes for it at once', (
      tester,
    ) async {
      backend.adapter.onJson(
        'PUT',
        ApiPaths.myVote(Ids.pollId),
        pollJson(
          myOptionIds: ['o2'],
          winningOptionIds: ['o2'],
          options: [
            pollOptionJson(id: 'o1', label: 'Dune'),
            pollOptionJson(
              id: 'o2',
              label: 'Up',
              position: 1,
              voters: [userPublicJson()],
            ),
          ],
        ),
      );
      await pumpCard(tester, pollJson());

      expect(find.byType(Radio<String>), findsNWidgets(2));
      await tester.tap(find.byType(Radio<String>).last);
      await tester.pumpAndSettle();

      expect(votesSent(), [
        ['o2'],
      ]);
      // The server's poll replaces the old one: my vote and the winner.
      final radio = tester.widget<RadioGroup<String>>(
        find.byType(RadioGroup<String>),
      );
      expect(radio.groupValue, 'o2');
      expect(find.byIcon(Icons.emoji_events), findsOneWidget);
      expect(find.text('Retract my vote'), findsOneWidget);
    });

    testWidgets('multiple choice: check several, then Save vote', (
      tester,
    ) async {
      backend.adapter.onJson(
        'PUT',
        ApiPaths.myVote(Ids.pollId),
        pollJson(allowMultiple: true, myOptionIds: ['o1', 'o2']),
      );
      await pumpCard(tester, pollJson(allowMultiple: true));

      final save = find.widgetWithText(FilledButton, 'Save vote');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).last);
      await tester.pump();
      expect(votesSent(), isEmpty); // nothing sent until saved
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(votesSent(), [
        ['o1', 'o2'],
      ]);
      expect(find.text('Retract my vote'), findsOneWidget);
    });

    testWidgets('a closed poll disables voting and adding options', (
      tester,
    ) async {
      await pumpCard(
        tester,
        pollJson(isOpen: false, closedAt: '2026-09-21T10:00:00Z'),
      );

      final radios = tester.widgetList<Radio<String>>(
        find.byType(Radio<String>),
      );
      expect(radios.every((r) => r.enabled == false), isTrue);
      expect(find.text('Add option'), findsNothing);
      expect(find.textContaining('Closed'), findsOneWidget);
    });

    testWidgets('manager actions only with can_manage', (tester) async {
      await pumpCard(tester, pollJson(canManage: false));
      expect(find.byTooltip('Manage poll'), findsNothing);
    });

    testWidgets('managers can close the poll', (tester) async {
      backend.adapter.onJson(
        'POST',
        '${ApiPaths.poll(Ids.pollId)}/close',
        pollJson(isOpen: false, closedAt: '2026-09-21T10:00:00Z'),
      );
      await pumpCard(tester, pollJson());

      await tester.tap(find.byTooltip('Manage poll'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close poll'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Closed'), findsOneWidget);
    });

    testWidgets('ties highlight every winner', (tester) async {
      await pumpCard(
        tester,
        pollJson(
          winningOptionIds: ['o1', 'o2'],
          options: [
            pollOptionJson(id: 'o1', label: 'Dune', voters: [userPublicJson()]),
            pollOptionJson(
              id: 'o2',
              label: 'Up',
              position: 1,
              voters: [userPublicJson(id: Ids.beaId, displayName: 'Bea')],
            ),
            pollOptionJson(id: 'o3', label: 'Heat', position: 2),
          ],
        ),
      );

      expect(find.byIcon(Icons.emoji_events), findsNWidgets(2));
      expect(find.text('2 voters', findRichText: true), findsNothing);
      expect(find.textContaining('2 voters'), findsOneWidget);
    });

    testWidgets('409 poll_closed reloads the polls and says so', (
      tester,
    ) async {
      backend.adapter.onProblem(
        'PUT',
        ApiPaths.myVote(Ids.pollId),
        409,
        'poll_closed',
      );
      await pumpCard(tester, pollJson());
      backend.adapter.onJson('GET', ApiPaths.polls(Ids.activityId), [
        pollJson(isOpen: false, closedAt: '2026-09-21T10:00:00Z'),
      ]);

      await tester.tap(find.byType(Radio<String>).first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Closed'), findsOneWidget);
      expect(
        backend.adapter.requestsTo('GET', ApiPaths.polls(Ids.activityId)),
        hasLength(2),
      );
    });
  });

  group('CreatePollSheet', () {
    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      backend.adapter.onJson('GET', ApiPaths.polls(Ids.activityId), []);
      await tester.pumpApp(
        const Scaffold(body: CreatePollSheet(activityId: Ids.activityId)),
        overrides: [
          ...backend.overrides,
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedIn()),
          ),
        ],
      );
    }

    testWidgets('needs a question and 2 distinct options', (tester) async {
      await pumpSheet(tester);

      expect(find.byTooltip('Remove option 1'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find
                  .widgetWithIcon(IconButton, Icons.remove_circle_outline)
                  .first,
            )
            .onPressed,
        isNull,
        reason: 'a poll keeps at least 2 options',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 1'),
        'Dune',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 2'),
        'DUNE',
      );
      await tester.tap(find.text('Create poll'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a question.'), findsOneWidget);
      expect(find.text('Already an option'), findsOneWidget);
      expect(
        backend.adapter.requestsTo('POST', ApiPaths.polls(Ids.activityId)),
        isEmpty,
      );
    });

    testWidgets('creates a multiple-choice poll', (tester) async {
      backend.adapter.onJson(
        'POST',
        ApiPaths.polls(Ids.activityId),
        pollJson(allowMultiple: true),
        status: 201,
      );
      await pumpSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Question'),
        'Which movie?',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 1'),
        'Dune',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 2'),
        'Up',
      );
      await tester.tap(find.text('Add an option'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Option 3'),
        'Heat',
      );
      await tester.tap(find.text('Allow several choices'));
      await tester.tap(find.text('Create poll'));
      await tester.pumpAndSettle();

      final body = backend.adapter
          .requestsTo('POST', ApiPaths.polls(Ids.activityId))
          .single
          .jsonMap;
      expect(body['question'], 'Which movie?');
      expect(body['allow_multiple'], isTrue);
      expect(body['closes_at'], isNull);
      expect(body['options'], [
        {'label': 'Dune', 'url': null},
        {'label': 'Up', 'url': null},
        {'label': 'Heat', 'url': null},
      ]);
    });
  });

  testWidgets('the Vote badge goes away once I have voted', (tester) async {
    backend
      ..stubGroup()
      ..stubBacklog(activities: [activitySummaryJson(myUnvotedPollCount: 1)])
      ..adapter.onJson('GET', ApiPaths.polls(Ids.activityId), [pollJson()])
      ..adapter.onJson(
        'PUT',
        ApiPaths.myVote(Ids.pollId),
        pollJson(myOptionIds: ['o1']),
      );
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await tester.pumpFriendsApp(
      overrides: [
        ...backend.overrides,
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedIn()),
        ),
      ],
      location: Routes.groupBacklog(Ids.groupId),
    );
    expect(find.byType(VoteBadge), findsOneWidget);

    // Voting (from the activity's detail) refreshes the backlog.
    backend.stubBacklog(activities: [activitySummaryJson()]);
    unawaited(
      container.read(pollsControllerProvider.notifier).vote(
        Poll.fromJson(pollJson()),
        ['o1'],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      backend.adapter.requestsTo('PUT', ApiPaths.myVote(Ids.pollId)),
      hasLength(1),
    );
    expect(find.byType(VoteBadge), findsNothing);
  });

  test('pollErrorMessages covers the poll-specific codes', () {
    expect(pollErrorMessages.keys, containsAll(['poll_closed', 'name_taken']));
  });
}
