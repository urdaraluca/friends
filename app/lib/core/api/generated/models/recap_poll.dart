// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'recap_poll.freezed.dart';
part 'recap_poll.g.dart';

@Freezed()
abstract class RecapPoll with _$RecapPoll {
  const factory RecapPoll({
    required String id,
    required String question,
    @JsonKey(name: 'activity_id')
    required String activityId,
    @JsonKey(name: 'activity_title')
    required String activityTitle,
    required int voters,
  }) = _RecapPoll;
  
  factory RecapPoll.fromJson(Map<String, Object?> json) => _$RecapPollFromJson(json);
}
