// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'recap_idea.freezed.dart';
part 'recap_idea.g.dart';

@Freezed()
abstract class RecapIdea with _$RecapIdea {
  const factory RecapIdea({
    @JsonKey(name: 'activity_id')
    required String activityId,
    required String title,
    required String? color,
    required int interested,
  }) = _RecapIdea;
  
  factory RecapIdea.fromJson(Map<String, Object?> json) => _$RecapIdeaFromJson(json);
}
