import 'package:friends/core/api/api_exception.dart';
import 'package:friends/core/api/api_providers.dart';
import 'package:friends/core/api/generated/export.dart';
import 'package:friends/features/backlog/data/backlog_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'backlog_controller.g.dart';

/// Every activity and category mutation (contract sections 8.6 and 8.7).
///
/// Each method throws `ApiException`s and, on success, invalidates what
/// changed: the backlog pagers and the activity for activity changes; the
/// categories, the pagers and every loaded activity for category changes
/// (a deleted category moves or uncategorises activities).
@Riverpod(keepAlive: true)
class BacklogController extends _$BacklogController {
  @override
  void build() {}

  ActivitiesClient get _activities => ref.read(activitiesClientProvider);

  CategoriesClient get _categories => ref.read(categoriesClientProvider);

  /// Everything derived from the backlog is stale: the pagers, the activity
  /// (when given), and every other list of activities.
  void activitiesChanged({String? activityId}) {
    ref.invalidate(activitiesPagerProvider);
    if (activityId != null) ref.invalidate(activityProvider(activityId));
  }

  // --- activities ---------------------------------------------------------

  /// `POST /groups/{id}/activities`. I become interested; a null owner
  /// means me.
  Future<Activity> createActivity(String groupId, ActivityCreate body) async {
    final activity = await apiCall(
      () => _activities.createActivity(groupId: groupId, body: body),
    );
    activitiesChanged(activityId: activity.id);
    return activity;
  }

  /// `PUT /activities/{id}` with the complete new state and the `version`
  /// last read: `409 version_conflict` when someone saved in between.
  Future<Activity> updateActivity(
    String activityId,
    ActivityUpdate body,
  ) async {
    final activity = await apiCall(
      () => _activities.updateActivity(activityId: activityId, body: body),
    );
    activitiesChanged(activityId: activityId);
    return activity;
  }

  /// `DELETE /activities/{id}` (its creator, its owner or an admin).
  Future<void> deleteActivity(String activityId) async {
    await apiCall(() => _activities.deleteActivity(activityId: activityId));
    activitiesChanged(activityId: activityId);
  }

  /// `POST /activities/{id}/status`. The same status changes nothing.
  Future<Activity> setStatus(String activityId, ActivityStatus status) async {
    final activity = await apiCall(
      () => _activities.setActivityStatus(
        activityId: activityId,
        body: StatusChange(status: status),
      ),
    );
    activitiesChanged(activityId: activityId);
    return activity;
  }

  /// `PUT` or `DELETE /activities/{id}/interest` (idempotent). The pagers
  /// are left alone: the card updates its own item, so the list doesn't
  /// jump.
  Future<InterestState> setInterest(
    String activityId, {
    required bool interested,
  }) async {
    final state = await apiCall(
      () => interested
          ? _activities.addInterest(activityId: activityId)
          : _activities.removeInterest(activityId: activityId),
    );
    ref.invalidate(activityProvider(activityId));
    return state;
  }

  // --- categories ---------------------------------------------------------

  /// `POST /groups/{id}/categories`.
  Future<Category> createCategory(String groupId, CategoryWrite body) async {
    final category = await apiCall(
      () => _categories.createCategory(groupId: groupId, body: body),
    );
    ref.invalidate(categoriesProvider(groupId));
    return category;
  }

  /// `PUT /categories/{id}` (its creator or an admin): the complete new
  /// state, `field_defs` included.
  Future<Category> updateCategory(
    String groupId,
    String categoryId,
    CategoryWrite body,
  ) async {
    final category = await apiCall(
      () => _categories.updateCategory(categoryId: categoryId, body: body),
    );
    _categoriesChanged(groupId);
    return category;
  }

  /// `DELETE /categories/{id}`: a subcategory's activities move to its
  /// parent; a top-level category's subcategories go too and its activities
  /// become uncategorised.
  Future<void> deleteCategory(String groupId, String categoryId) async {
    await apiCall(() => _categories.deleteCategory(categoryId: categoryId));
    _categoriesChanged(groupId);
  }

  void _categoriesChanged(String groupId) {
    ref
      ..invalidate(categoriesProvider(groupId))
      ..invalidate(activityProvider);
    activitiesChanged();
  }
}
