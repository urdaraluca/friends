// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/recap.dart';
import '../models/recap_period.dart';

part 'recap_client.g.dart';

@RestApi()
abstract class RecapClient {
  factory RecapClient(Dio dio, {String? baseUrl}) = _RecapClient;

  /// Get Group Recap.
  ///
  /// The group's highlights for a month or a year.
  ///
  /// Memories made, the most active planners, the top categories and a few extras.
  /// Only past and current periods, in the group's timezone.
  ///
  /// [start] - The period's first day (the 1st of a month, or 1 January), in the group's timezone. Omitted: the current period.
  @GET('/api/v1/groups/{group_id}/recap')
  Future<Recap> getGroupRecap({
    @Path('group_id') required String groupId,
    @Query('period') required RecapPeriod period,
    @Query('start') DateTime? start,
  });
}
