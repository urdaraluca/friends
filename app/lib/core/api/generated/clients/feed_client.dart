// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

import '../models/feed_page.dart';

part 'feed_client.g.dart';

@RestApi()
abstract class FeedClient {
  factory FeedClient(Dio dio, {String? baseUrl}) = _FeedClient;

  /// List Group Feed.
  ///
  /// What happened in the group, newest first: ideas, events, polls, the wheel and members.
  ///
  /// [cursor] - Opaque: the `next_cursor` of the previous page.
  @GET('/api/v1/groups/{group_id}/feed')
  Future<FeedPage> listGroupFeed({
    @Path('group_id') required String groupId,
    @Query('limit') int? limit = 50,
    @Query('cursor') String? cursor,
  });
}
