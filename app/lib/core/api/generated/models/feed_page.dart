// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'feed_item.dart';

part 'feed_page.freezed.dart';
part 'feed_page.g.dart';

@Freezed()
abstract class FeedPage with _$FeedPage {
  const factory FeedPage({
    required List<FeedItem> items,
    @JsonKey(name: 'next_cursor')
    required String? nextCursor,
  }) = _FeedPage;
  
  factory FeedPage.fromJson(Map<String, Object?> json) => _$FeedPageFromJson(json);
}
