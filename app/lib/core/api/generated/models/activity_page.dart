// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_summary.dart';

part 'activity_page.freezed.dart';
part 'activity_page.g.dart';

@Freezed()
abstract class ActivityPage with _$ActivityPage {
  const factory ActivityPage({
    required List<ActivitySummary> items,
    @JsonKey(name: 'next_cursor')
    required String? nextCursor,
  }) = _ActivityPage;
  
  factory ActivityPage.fromJson(Map<String, Object?> json) => _$ActivityPageFromJson(json);
}
