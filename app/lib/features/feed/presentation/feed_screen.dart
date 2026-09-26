import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/feed/data/feed_providers.dart';
import 'package:friends/features/feed/domain/feed_text.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// `/groups/:groupId/feed`: what happened in the group, newest first
/// (contract section 15). Tap an item to open what it is about.
class FeedScreen extends ConsumerWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = groupFeedProvider(groupId);
    final feed = ref.watch(provider);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go(Routes.groupHub(groupId)),
              ),
        title: const Text("What's new"),
      ),
      body: AsyncValueView(
        value: feed,
        onRetry: () => ref.invalidate(provider),
        data: (list) => RefreshIndicator(
          onRefresh: () => settled([ref.refresh(provider.future)]),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: list.items.length + (list.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= list.items.length) {
                    scheduleMicrotask(
                      () => unawaited(ref.read(provider.notifier).loadMore()),
                    );
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final item = list.items[index];
                  return FeedTile(groupId: groupId, item: item, now: now);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One feed item: an icon for its kind, the sentence, and when.
class FeedTile extends StatelessWidget {
  const new({
    required this.groupId,
    required this.item,
    required this.now,
    super.key,
  });

  final String groupId;
  final FeedItem item;
  final DateTime now;

  static IconData icon(FeedItem item) => switch (item.action) {
    'activity.status_changed' when _to(item) == 'done' => Icons.celebration,
    'activity.interest_added' => Icons.favorite_border,
    'member.joined' => Icons.person_add_alt,
    'member.left' || 'member.removed' => Icons.person_remove_alt_1,
    final action when action.startsWith('member.') => Icons.manage_accounts,
    final action when action.startsWith('group.') => Icons.groups_outlined,
    final action when action.startsWith('event.') => Icons.event,
    final action when action.startsWith('poll.') => Icons.how_to_vote,
    final action when action.startsWith('wheel.') => Icons.casino_outlined,
    _ => Icons.lightbulb_outline,
  };

  static String? _to(FeedItem item) {
    final data = item.data;
    return data is Map ? data['to'] as String? : null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final target = feedTarget(groupId, item);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        child: Icon(icon(item), size: 20),
      ),
      title: Text.rich(
        TextSpan(
          children: [
            for (final span in feedSentence(item))
              TextSpan(
                text: span.text,
                style: span.bold
                    ? const TextStyle(fontWeight: FontWeight.w600)
                    : null,
              ),
          ],
        ),
      ),
      subtitle: Text(feedTime(item.createdAt, now)),
      onTap: target == null ? null : () => unawaited(context.push(target)),
    );
  }
}
