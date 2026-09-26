import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/polls/data/polls_providers.dart';
import 'package:friends/features/polls/presentation/poll_card.dart';
import 'package:friends/features/polls/presentation/poll_dialogs.dart';
import 'package:material_ui/material_ui.dart';

/// Polls per activity (contract section 1.9).
const maxPollsPerActivity = 10;

/// The "Polls" section of an activity: its polls, oldest first, and "New
/// poll".
class PollsSection extends ConsumerWidget {
  const new({required this.activity, super.key});

  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final polls = ref.watch(pollsProvider(activity.id));
    final count = polls.value?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Polls',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              TextButton.icon(
                onPressed: polls.hasValue && count < maxPollsPerActivity
                    ? () => unawaited(showCreatePollSheet(context, activity.id))
                    : null,
                icon: const Icon(Icons.how_to_vote_outlined),
                label: const Text('New poll'),
              ),
            ],
          ),
          AsyncValueView(
            value: polls,
            onRetry: () => ref.invalidate(pollsProvider(activity.id)),
            loading: const Padding(
              padding: EdgeInsets.all(16),
              child: LoadingView(),
            ),
            data: (polls) => polls.isEmpty
                ? Text(
                    'Can\'t decide? Ask the group: "Which movie?", "Which '
                    'restaurant?"',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Column(
                    children: [
                      for (final poll in polls)
                        PollCard(key: ValueKey(poll.id), poll: poll),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
