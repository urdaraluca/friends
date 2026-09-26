import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/backlog/domain/activity_filter.dart';
import 'package:friends/features/backlog/domain/category_index.dart';
import 'package:material_ui/material_ui.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backlog_providers.g.dart';

/// A group's categories: top-level ones (by position, then name), each with
/// its subcategories (`GET /groups/{id}/categories`).
@riverpod
Future<List<CategoryNode>> categories(Ref ref, String groupId) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(categoriesClientProvider);
  return apiCall(() => client.listCategories(groupId: groupId));
}

/// [categoriesProvider] indexed by ID.
@riverpod
Future<CategoryIndex> categoryIndex(Ref ref, String groupId) async =>
    CategoryIndex(await ref.watch(categoriesProvider(groupId).future));

/// One activity with everything the detail screen shows
/// (`GET /activities/{id}`).
@riverpod
Future<Activity> activity(Ref ref, String activityId) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(activitiesClientProvider);
  return apiCall(() => client.getActivity(activityId: activityId));
}

/// The backlog's filters and sort for a group. Kept for the session, so
/// they survive switching tabs and opening an activity.
@Riverpod(keepAlive: true)
class BacklogFilter extends _$BacklogFilter {
  @override
  ActivityFilter build(String groupId) {
    ref.watch(currentUserIdProvider);
    return const ActivityFilter();
  }

  // A setter-like method: Riverpod notifiers expose state changes as calls.
  // ignore: use_setters_to_change_properties
  void set(ActivityFilter filter) => state = filter;
}

/// The pages of the backlog loaded so far.
@immutable
class ActivityList {
  const new({
    required this.items,
    required this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<ActivitySummary> items;

  /// The cursor of the next page, or null after the last page.
  final String? nextCursor;

  /// A next page is on its way.
  final bool loadingMore;

  /// Why the last `loadMore` failed (the list shows Retry), or null.
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  ActivityList copyWith({
    List<ActivitySummary>? items,
    bool? loadingMore,
    Object? Function()? loadMoreError,
  }) => ActivityList(
    items: items ?? this.items,
    nextCursor: nextCursor,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError == null ? this.loadMoreError : loadMoreError(),
  );
}

/// The backlog of [groupId] matching [filter], one cursor page at a time
/// (contract sections 1.6 and 8.7).
///
/// The first page loads with the provider; [loadMore] appends the next one
/// until `next_cursor` is null.
@riverpod
class ActivitiesPager extends _$ActivitiesPager {
  static const pageSize = 30;

  @override
  Future<ActivityList> build(String groupId, ActivityFilter filter) async {
    final me = ref.watch(currentUserIdProvider);
    final page = await _fetch(me, cursor: null);
    return ActivityList(items: page.items, nextCursor: page.nextCursor);
  }

  Future<ActivityPage> _fetch(String? me, {required String? cursor}) {
    final client = ref.read(activitiesClientProvider);
    return apiCall(
      () => client.listActivities(
        groupId: groupId,
        status: filter.queryStatuses,
        categoryId: filter.categoryId,
        includeSubcategories: filter.includeSubcategories,
        interestedBy: filter.onlyInterested ? me : null,
        ownerId: filter.onlyMine ? me : null,
        costMax: filter.costMax,
        includeUnpriced: filter.includeUnpriced,
        q: filter.queryText,
        sort: filter.sort,
        order: filter.order,
        cursor: cursor,
        limit: pageSize,
      ),
    );
  }

  /// Appends the next page. Does nothing while one is loading or after the
  /// last page; a failure is kept in [ActivityList.loadMoreError].
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final loading = current.copyWith(
      loadingMore: true,
      loadMoreError: () => null,
    );
    state = AsyncData(loading);
    try {
      final page = await _fetch(
        ref.read(currentUserIdProvider),
        cursor: current.nextCursor,
      );
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(
        ActivityList(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on Object catch (error) {
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: () => error),
      );
    }
  }

  /// Replaces the loaded item with [activityId], e.g. for an optimistic
  /// interest toggle. Does nothing if it isn't loaded.
  void updateItem(
    String activityId,
    ActivitySummary Function(ActivitySummary item) update,
  ) {
    final current = state.value;
    if (current == null) return;
    final index = current.items.indexWhere((item) => item.id == activityId);
    if (index < 0) return;
    final items = [...current.items];
    items[index] = update(items[index]);
    state = AsyncData(current.copyWith(items: items));
  }
}
