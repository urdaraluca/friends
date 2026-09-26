// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_public.dart';

part 'feed_item.freezed.dart';
part 'feed_item.g.dart';

/// One ``group_log`` row, as members see it.
@Freezed()
abstract class FeedItem with _$FeedItem {
  const factory FeedItem({
    required String id,
    required String action,
    required UserPublic? actor,
    @JsonKey(name: 'subject_type')
    required String? subjectType,
    @JsonKey(name: 'subject_id')
    required String? subjectId,
    @JsonKey(name: 'subject_title')
    required String? subjectTitle,
    @JsonKey(name: 'subject_exists')
    required bool subjectExists,
    required dynamic data,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
  }) = _FeedItem;
  
  factory FeedItem.fromJson(Map<String, Object?> json) => _$FeedItemFromJson(json);
}
