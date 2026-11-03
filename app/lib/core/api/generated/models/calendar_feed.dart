// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'calendar_feed.freezed.dart';
part 'calendar_feed.g.dart';

/// My webcal subscription (contract section 5.10). Both URLs are null when it is off.
@Freezed()
abstract class CalendarFeed with _$CalendarFeed {
  const factory CalendarFeed({
    required String? url,
    @JsonKey(name: 'webcal_url')
    required String? webcalUrl,
  }) = _CalendarFeed;
  
  factory CalendarFeed.fromJson(Map<String, Object?> json) => _$CalendarFeedFromJson(json);
}
