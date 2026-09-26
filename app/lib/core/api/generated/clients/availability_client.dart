// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/group_availability.dart';

part 'availability_client.g.dart';

@RestApi()
abstract class AvailabilityClient {
  factory AvailabilityClient(Dio dio, {String? baseUrl}) = _AvailabilityClient;

  /// Get Group Availability.
  ///
  /// The current members' availability per day and slot in ``[from, to)``, and the best days.
  /// (score = free + 0.5 * maybe, then fewer busy, then the earliest). Who is free or maybe is.
  /// listed by name; busy is a count only.
  ///
  /// [from] - First day (inclusive).
  ///
  /// [to] - Last day (exclusive); at most 92 days after `from`.
  @GET('/api/v1/groups/{group_id}/availability')
  Future<GroupAvailability> getGroupAvailability({
    @Path('group_id') required String groupId,
    @Query('from') required DateTime from,
    @Query('to') required DateTime to,
  });
}
