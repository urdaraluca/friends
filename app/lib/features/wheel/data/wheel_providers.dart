import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/core/auth/auth_controller.dart';
import 'package:friends/features/backlog/data/backlog_controller.dart';
import 'package:material_ui/material_ui.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'wheel_providers.g.dart';

/// The wheel's default statuses (contract section 10).
const List<ActivityStatus> wheelDefaultStatuses = [
  ActivityStatus.idea,
  ActivityStatus.planning,
];

/// The wheel's filters for a group. "Only ideas I'm interested in" starts
/// ON: the client sends `interested_by=<me>` (the server has no default).
@Riverpod(keepAlive: true)
class WheelFilter extends _$WheelFilter {
  @override
  WheelFilters build(String groupId) {
    final me = ref.watch(currentUserIdProvider);
    return WheelFilters(status: wheelDefaultStatuses, interestedBy: me);
  }

  // A setter-like method: Riverpod notifiers expose state changes as calls.
  // ignore: use_setters_to_change_properties
  void set(WheelFilters filters) => state = filters;
}

/// The candidate pool for [filters]: the first 50 by newest, and the pool's
/// size (`GET /groups/{id}/wheel/candidates`).
@riverpod
Future<WheelCandidates> wheelCandidates(
  Ref ref,
  String groupId,
  WheelFilters filters,
) {
  ref.watch(currentUserIdProvider);
  final client = ref.watch(wheelClientProvider);
  return apiCall(
    () => client.listWheelCandidates(
      groupId: groupId,
      status: filters.status,
      categoryId: filters.categoryId,
      includeSubcategories: filters.includeSubcategories,
      interestedBy: filters.interestedBy,
      ownerId: filters.ownerId,
      costMax: filters.costMax,
      includeUnpriced: filters.includeUnpriced,
      dueBefore: filters.dueBefore,
    ),
  );
}

/// Spins loaded so far.
@immutable
class SpinList {
  const new({required this.items, required this.nextCursor, this.loading});

  final List<WheelSpin> items;
  final String? nextCursor;

  /// A next page on its way.
  final bool? loading;

  bool get hasMore => nextCursor != null;
}

/// A group's spin history, newest first, one cursor page at a time.
@riverpod
class SpinHistory extends _$SpinHistory {
  static const pageSize = 30;

  @override
  Future<SpinList> build(String groupId) async {
    ref.watch(currentUserIdProvider);
    final page = await _fetch(null);
    return SpinList(items: page.items, nextCursor: page.nextCursor);
  }

  Future<WheelSpinPage> _fetch(String? cursor) {
    final client = ref.read(wheelClientProvider);
    return apiCall(
      () => client.listSpins(groupId: groupId, cursor: cursor, limit: pageSize),
    );
  }

  /// Appends the next page, if any.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loading == true) return;
    final loading = SpinList(
      items: current.items,
      nextCursor: current.nextCursor,
      loading: true,
    );
    state = AsyncData(loading);
    try {
      final page = await _fetch(current.nextCursor);
      if (!ref.mounted || !identical(state.value, loading)) return;
      state = AsyncData(
        SpinList(
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

/// Spinning and accepting (contract sections 8.10 and 10).
@Riverpod(keepAlive: true)
class WheelController extends _$WheelController {
  @override
  void build() {}

  WheelClient get _client => ref.read(wheelClientProvider);

  /// `POST /groups/{id}/wheel/spins`: the server picks the result.
  Future<WheelSpin> spin(String groupId, SpinCreate body) async {
    final spin = await apiCall(
      () => _client.createSpin(groupId: groupId, body: body),
    );
    ref.invalidate(spinHistoryProvider(groupId));
    return spin;
  }

  /// `POST /wheel/spins/{id}/accept`: an idea becomes planning. Accepting
  /// again returns the spin unchanged; `409 result_deleted` when the
  /// activity is gone.
  Future<WheelSpin> accept(WheelSpin spin) async {
    final accepted = await apiCall(() => _client.acceptSpin(spinId: spin.id));
    ref.invalidate(spinHistoryProvider(spin.groupId));
    ref
        .read(backlogControllerProvider.notifier)
        .activitiesChanged(activityId: spin.resultActivityId);
    return accepted;
  }
}
