// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/activity_status.dart';
import '../models/spin_create.dart';
import '../models/wheel_candidates.dart';
import '../models/wheel_spin.dart';
import '../models/wheel_spin_page.dart';

part 'wheel_client.g.dart';

@RestApi()
abstract class WheelClient {
  factory WheelClient(Dio dio, {String? baseUrl}) = _WheelClient;

  /// List Wheel Candidates.
  ///
  /// `WheelFilters` as query parameters: the pool's size and its first 50 activities, newest.
  /// first.
  ///
  /// [status] - Repeat the key for several. Omitted: idea and planning.
  ///
  /// [includeSubcategories] - With `category_id`: also its subcategories.
  ///
  /// [costMax] - `estimated_cost <= cost_max` in the group's currency.
  ///
  /// [includeUnpriced] - With `cost_max`: also activities without a cost or in another currency.
  ///
  /// [dueBefore] - `due_date <= due_before` (inclusive).
  @GET('/api/v1/groups/{group_id}/wheel/candidates')
  Future<WheelCandidates> listWheelCandidates({
    @Path('group_id') required String groupId,
    @Query('include_subcategories') bool? includeSubcategories = true,
    @Query('include_unpriced') bool? includeUnpriced = true,
    @Query('status') List<ActivityStatus>? status,
    @Query('category_id') String? categoryId,
    @Query('interested_by') String? interestedBy,
    @Query('owner_id') String? ownerId,
    @Query('cost_max') int? costMax,
    @Query('due_before') DateTime? dueBefore,
  });

  /// Create Spin.
  ///
  /// The server picks the result, every slice with the same weight. Without `activity_ids`.
  /// the slices are the filtered pool (a random 50 when it is larger), newest first; with them,.
  /// those activities in that order, and the filters are only stored.
  @POST('/api/v1/groups/{group_id}/wheel/spins')
  Future<WheelSpin> createSpin({
    @Path('group_id') required String groupId,
    @Body() required SpinCreate body,
  });

  /// List Spins.
  ///
  /// The spin history, newest first.
  ///
  /// [cursor] - Opaque: the `next_cursor` of the previous page.
  @GET('/api/v1/groups/{group_id}/wheel/spins')
  Future<WheelSpinPage> listSpins({
    @Path('group_id') required String groupId,
    @Query('limit') int? limit = 50,
    @Query('cursor') String? cursor,
  });

  /// Accept Spin.
  ///
  /// Any member. An idea moves to planning; other statuses stay. Accepting again returns the.
  /// spin unchanged.
  @POST('/api/v1/wheel/spins/{spin_id}/accept')
  Future<WheelSpin> acceptSpin({
    @Path('spin_id') required String spinId,
  });
}
