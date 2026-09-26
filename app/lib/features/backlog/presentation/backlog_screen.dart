import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:friends/core/api/api_error_messages.dart';
import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/router/routes.dart';
import 'package:friends/core/widgets/async_value_view.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:friends/features/backlog/domain/activity_filter.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:friends/features/backlog/presentation/widgets/activity_card.dart';
import 'package:friends/features/backlog/presentation/widgets/backlog_filter_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// The Backlog tab (`/groups/:groupId/backlog`): search, filters and sort,
/// then the group's activities one page at a time.
class BacklogScreen extends ConsumerWidget {
  const new({required this.groupId, super.key});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(backlogFilterProvider(groupId));
    final categories =
        ref.watch(categoryIndexProvider(groupId)).value ??
        CategoryIndex.empty();
    return Scaffold(
      body: Column(
        children: [
          BacklogFilterBar(
            groupId: groupId,
            filter: filter,
            categories: categories,
            onChanged: (next) =>
                ref.read(backlogFilterProvider(groupId).notifier).set(next),
          ),
          Expanded(
            child: ActivityListView(
              groupId: groupId,
              filter: filter,
              categories: categories,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-idea',
        onPressed: () => unawaited(context.push(Routes.newActivity(groupId))),
        icon: const Icon(Icons.add),
        label: const Text('New idea'),
      ),
    );
  }
}

/// The paged list for [filter], with pull to refresh, loading more near the
/// end, and empty and error states.
class ActivityListView extends ConsumerWidget {
  const new({
    required this.groupId,
    required this.filter,
    required this.categories,
    super.key,
  });

  final String groupId;
  final ActivityFilter filter;
  final CategoryIndex categories;

  /// Starts loading the next page this many items before the end.
  static const _loadAhead = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = activitiesPagerProvider(groupId, filter);
    final pager = ref.watch(provider);
    return AsyncValueView(
      value: pager,
      onRetry: () => ref.invalidate(provider),
      data: (list) {
        Future<void> refresh() => settled([
          ref.refresh(provider.future),
          ref.refresh(categoriesProvider(groupId).future),
        ]);
        if (list.items.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: _EmptyBacklog(
              filtered: filter.isFiltered,
              onClearFilters: () => ref
                  .read(backlogFilterProvider(groupId).notifier)
                  .set(ActivityFilter(sort: filter.sort, order: filter.order)),
              onAdd: () => unawaited(context.push(Routes.newActivity(groupId))),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 4, bottom: 88),
            itemCount: list.items.length + 1,
            itemBuilder: (context, index) {
              if (index >= list.items.length - _loadAhead &&
                  list.hasMore &&
                  !list.loadingMore &&
                  list.loadMoreError == null) {
                scheduleMicrotask(
                  () => unawaited(ref.read(provider.notifier).loadMore()),
                );
              }
              if (index == list.items.length) {
                return _ListFooter(
                  list: list,
                  onRetry: () =>
                      unawaited(ref.read(provider.notifier).loadMore()),
                );
              }
              final item = list.items[index];
              return ActivityCard(
                key: ValueKey(item.id),
                activity: item,
                categories: categories,
                onTap: () =>
                    unawaited(context.push(Routes.activity(groupId, item.id))),
                onToggleInterest: () =>
                    unawaited(_toggleInterest(context, ref, item)),
              );
            },
          ),
        );
      },
    );
  }

  /// Flips my interest on the card at once, then confirms with the server's
  /// counts, or rolls back and says why.
  Future<void> _toggleInterest(
    BuildContext context,
    WidgetRef ref,
    ActivitySummary item,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final pager = ref.read(activitiesPagerProvider(groupId, filter).notifier);
    final interested = !item.iAmInterested;
    pager.updateItem(
      item.id,
      (a) => a.copyWith(
        iAmInterested: interested,
        interestCount: a.interestCount + (interested ? 1 : -1),
      ),
    );
    try {
      final state = await ref
          .read(backlogControllerProvider.notifier)
          .setInterest(item.id, interested: interested);
      pager.updateItem(
        item.id,
        (a) => a.copyWith(
          iAmInterested: state.interested,
          interestCount: state.interestCount,
        ),
      );
    } on ApiException catch (error) {
      pager.updateItem(
        item.id,
        (a) => a.copyWith(
          iAmInterested: item.iAmInterested,
          interestCount: item.interestCount,
        ),
      );
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}

class _ListFooter extends StatelessWidget {
  const new({required this.list, required this.onRetry});

  final ActivityList list;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (list.loadMoreError case final error?) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(friendlyErrorMessage(error), textAlign: TextAlign.center),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (list.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 8);
  }
}

class _EmptyBacklog extends StatelessWidget {
  const new({
    required this.filtered,
    required this.onClearFilters,
    required this.onAdd,
  });

  final bool filtered;
  final VoidCallback onClearFilters;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    filtered ? Icons.filter_alt_off_outlined : Icons.lightbulb,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    filtered ? 'Nothing matches these filters' : 'No ideas yet',
                    style: textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    filtered
                        ? 'Try other filters, or clear them.'
                        : 'Collect things you want to do together: movies, '
                              'trips, dinners, games…',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  if (filtered)
                    OutlinedButton(
                      onPressed: onClearFilters,
                      child: const Text('Clear filters'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add the first idea'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
