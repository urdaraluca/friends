import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:material_ui/material_ui.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'feed_providers.g.dart';

/// Feed items loaded so far.
@immutable
class FeedList {
  const new({required this.items, required this.nextCursor, this.loading});

  final List<FeedItem> items;
  final String? nextCursor;

  /// A next page on its way.
  final bool? loading;

  bool get hasMore => nextCursor != null;
}

/// A group's feed (contract section 15), newest first, one cursor page at a
/// time.
@riverpod
class GroupFeed extends _$GroupFeed {
  static const pageSize = 40;

  @override
  Future<FeedList> build(String groupId) async {
    ref.watch(currentUserIdProvider);
    final page = await _fetch(null);
    return FeedList(items: page.items, nextCursor: page.nextCursor);
  }

  Future<FeedPage> _fetch(String? cursor) {
    final client = ref.read(feedClientProvider);
    return apiCall(
      () => client.listGroupFeed(
        groupId: groupId,
        cursor: cursor,
        limit: pageSize,
      ),
    );
  }

  /// Appends the next page, if any.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loading == true) return;
    final loading = FeedList(
      items: current.items,
      nextCursor: current.nextCursor,
      loading: true,
    );
    state = AsyncData(loading);
    try {
      final page = await _fetch(current.nextCursor);
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(
        FeedList(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } on Object {
      if (ref.mounted && identical(state.value, loading)) {
        state = AsyncData(current);
      }
    }
  }
}
