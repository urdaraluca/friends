// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_public.dart';

part 'interest_state.freezed.dart';
part 'interest_state.g.dart';

@Freezed()
abstract class InterestState with _$InterestState {
  const factory InterestState({
    @JsonKey(name: 'activity_id')
    required String activityId,
    required bool interested,
    @JsonKey(name: 'interest_count')
    required int interestCount,
    @JsonKey(name: 'interested_users')
    required List<UserPublic> interestedUsers,
  }) = _InterestState;
  
  factory InterestState.fromJson(Map<String, Object?> json) => _$InterestStateFromJson(json);
}
