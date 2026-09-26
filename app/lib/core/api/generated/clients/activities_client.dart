// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/activity.dart';
import '../models/activity_create.dart';
import '../models/activity_page.dart';
import '../models/activity_sort.dart';
import '../models/activity_status.dart';
import '../models/activity_update.dart';
import '../models/interest_state.dart';
import '../models/sort_order.dart';
import '../models/status_change.dart';

part 'activities_client.g.dart';

@RestApi()
abstract class ActivitiesClient {
  factory ActivitiesClient(Dio dio, {String? baseUrl}) = _ActivitiesClient;

  /// List Activities.
  ///
  /// The backlog, cursor-paginated. Due date and cost sort with nulls last; ties are broken.
  /// by id (descending).
  ///
  /// [status] - Repeat the key for several. Omitted: idea, planning and scheduled; done and dropped are the archive.
  ///
  /// [includeSubcategories] - With `category_id`: also its subcategories.
  ///
  /// [costMax] - `estimated_cost <= cost_max` in the group's currency.
  ///
  /// [includeUnpriced] - With `cost_max`: also activities without a cost or in another currency.
  ///
  /// [dueBefore] - `due_date <= due_before` (inclusive).
  ///
  /// [q] - Case-insensitive title substring.
  ///
  /// [cursor] - Opaque: the `next_cursor` of the previous page.
  @GET('/api/v1/groups/{group_id}/activities')
  Future<ActivityPage> listActivities({
    @Path('group_id') required String groupId,
    @Query('include_subcategories') bool? includeSubcategories = true,
    @Query('include_unpriced') bool? includeUnpriced = true,
    @Query('sort') ActivitySort? sort = ActivitySort.createdAt,
    @Query('order') SortOrder? order = SortOrder.desc,
    @Query('limit') int? limit = 50,
    @Query('status') List<ActivityStatus>? status,
    @Query('category_id') String? categoryId,
    @Query('owner_id') String? ownerId,
    @Query('interested_by') String? interestedBy,
    @Query('cost_max') int? costMax,
    @Query('due_before') DateTime? dueBefore,
    @Query('q') String? q,
    @Query('cursor') String? cursor,
  });

  /// Create Activity.
  ///
  /// The creator is marked interested. ``owner_id: null`` means the creator.
  @POST('/api/v1/groups/{group_id}/activities')
  Future<Activity> createActivity({
    @Path('group_id') required String groupId,
    @Body() required ActivityCreate body,
  });

  /// Get Activity
  @GET('/api/v1/activities/{activity_id}')
  Future<Activity> getActivity({
    @Path('activity_id') required String activityId,
  });

  /// Update Activity.
  ///
  /// Replaces the content; send the ``version`` you last read. ``owner_id: null`` means.
  /// unowned. A member may claim an unowned activity, the owner may hand it to anyone or to.
  /// nobody, and admins may do anything.
  @PUT('/api/v1/activities/{activity_id}')
  Future<Activity> updateActivity({
    @Path('activity_id') required String activityId,
    @Body() required ActivityUpdate body,
  });

  /// Delete Activity.
  ///
  /// The creator, the owner or an admin.
  @DELETE('/api/v1/activities/{activity_id}')
  Future<void> deleteActivity({
    @Path('activity_id') required String activityId,
  });

  /// Set Activity Status.
  ///
  /// Any transition is allowed; the same status changes nothing.
  @POST('/api/v1/activities/{activity_id}/status')
  Future<Activity> setActivityStatus({
    @Path('activity_id') required String activityId,
    @Body() required StatusChange body,
  });

  /// Add Interest.
  ///
  /// Marks the caller as interested (idempotent).
  @PUT('/api/v1/activities/{activity_id}/interest')
  Future<InterestState> addInterest({
    @Path('activity_id') required String activityId,
  });

  /// Remove Interest.
  ///
  /// Removes the caller's interest (idempotent).
  @DELETE('/api/v1/activities/{activity_id}/interest')
  Future<InterestState> removeInterest({
    @Path('activity_id') required String activityId,
  });
}
