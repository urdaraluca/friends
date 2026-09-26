import 'package:flutter/foundation.dart';
import 'package:friends/core/api/generated/export.dart';

/// The backlog's filters and sort: the query of
/// `GET /groups/{id}/activities` (contract section 8.7).
///
/// An immutable value with value equality, so
/// `activitiesPagerProvider(groupId, filter)` reuses the same pager for an
/// equal filter.
@immutable
class ActivityFilter {
  const new({
    this.statuses = activeStatuses,
    this.showArchived = false,
    this.categoryId,
    this.includeSubcategories = true,
    this.onlyInterested = false,
    this.onlyMine = false,
    this.costMax,
    this.includeUnpriced = true,
    this.query = '',
    this.sort = ActivitySort.createdAt,
    this.order = SortOrder.desc,
  });

  /// The server's default: the active backlog.
  static const Set<ActivityStatus> activeStatuses = {
    ActivityStatus.idea,
    ActivityStatus.planning,
    ActivityStatus.scheduled,
  };

  /// The archive, added by "Show archived".
  static const Set<ActivityStatus> archivedStatuses = {
    ActivityStatus.done,
    ActivityStatus.dropped,
  };

  /// The active statuses shown (a subset of [activeStatuses]).
  final Set<ActivityStatus> statuses;

  /// Also show done and dropped activities.
  final bool showArchived;

  /// Only this category (and, with [includeSubcategories], its
  /// subcategories).
  final String? categoryId;
  final bool includeSubcategories;

  /// "I'm interested" (`interested_by=<me>`).
  final bool onlyInterested;

  /// "Mine" (`owner_id=<me>`).
  final bool onlyMine;

  /// `estimated_cost <= costMax` in the group's currency.
  final int? costMax;

  /// With [costMax]: also activities without a cost (or in another
  /// currency).
  final bool includeUnpriced;

  /// Title search (`q`); blank means none.
  final String query;
  final ActivitySort sort;
  final SortOrder order;

  /// The `status` values to send, in enum order.
  List<ActivityStatus> get queryStatuses => [
    for (final status in ActivityStatus.values)
      if (statuses.contains(status) ||
          (showArchived && archivedStatuses.contains(status)))
        status,
  ];

  /// The `q` to send, or null.
  String? get queryText {
    final text = query.trim();
    return text.isEmpty ? null : text;
  }

  /// Whether any filter differs from the default (the sort doesn't count).
  bool get isFiltered =>
      !setEquals(statuses, activeStatuses) ||
      showArchived ||
      categoryId != null ||
      onlyInterested ||
      onlyMine ||
      costMax != null ||
      queryText != null;

  /// A copy with the given fields replaced. Nullable fields take a function
  /// so they can be cleared: `copyWith(categoryId: () => null)`.
  ActivityFilter copyWith({
    Set<ActivityStatus>? statuses,
    bool? showArchived,
    String? Function()? categoryId,
    bool? includeSubcategories,
    bool? onlyInterested,
    bool? onlyMine,
    int? Function()? costMax,
    bool? includeUnpriced,
    String? query,
    ActivitySort? sort,
    SortOrder? order,
  }) {
    return ActivityFilter(
      statuses: statuses ?? this.statuses,
      showArchived: showArchived ?? this.showArchived,
      categoryId: categoryId == null ? this.categoryId : categoryId(),
      includeSubcategories: includeSubcategories ?? this.includeSubcategories,
      onlyInterested: onlyInterested ?? this.onlyInterested,
      onlyMine: onlyMine ?? this.onlyMine,
      costMax: costMax == null ? this.costMax : costMax(),
      includeUnpriced: includeUnpriced ?? this.includeUnpriced,
      query: query ?? this.query,
      sort: sort ?? this.sort,
      order: order ?? this.order,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ActivityFilter &&
      setEquals(other.statuses, statuses) &&
      other.showArchived == showArchived &&
      other.categoryId == categoryId &&
      other.includeSubcategories == includeSubcategories &&
      other.onlyInterested == onlyInterested &&
      other.onlyMine == onlyMine &&
      other.costMax == costMax &&
      other.includeUnpriced == includeUnpriced &&
      other.query == query &&
      other.sort == sort &&
      other.order == order;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(statuses),
    showArchived,
    categoryId,
    includeSubcategories,
    onlyInterested,
    onlyMine,
    costMax,
    includeUnpriced,
    query,
    sort,
    order,
  );

  @override
  String toString() =>
      'ActivityFilter(${queryStatuses.map((s) => s.name).join(',')}, '
      'category: $categoryId, interested: $onlyInterested, mine: $onlyMine, '
      'costMax: $costMax, q: $query, ${sort.name} ${order.name})';
}
