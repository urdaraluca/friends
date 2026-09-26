// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'recap_activity.freezed.dart';
part 'recap_activity.g.dart';

@Freezed()
abstract class RecapActivity with _$RecapActivity {
  const factory RecapActivity({
    required String id,
    required String title,
    @JsonKey(name: 'category_id')
    required String? categoryId,
    required String? color,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'completed_at')
    required DateTime completedAt,
  }) = _RecapActivity;
  
  factory RecapActivity.fromJson(Map<String, Object?> json) => _$RecapActivityFromJson(json);
}
