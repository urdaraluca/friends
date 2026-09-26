// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'poll_option.dart';
import 'user_public.dart';

part 'poll.freezed.dart';
part 'poll.g.dart';

@Freezed()
abstract class Poll with _$Poll {
  const factory Poll({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    @JsonKey(name: 'activity_id')
    required String activityId,
    required String question,
    @JsonKey(name: 'allow_multiple')
    required bool allowMultiple,
    @JsonKey(name: 'closes_at')
    required DateTime? closesAt,
    @JsonKey(name: 'closed_at')
    required DateTime? closedAt,
    @JsonKey(name: 'is_open')
    required bool isOpen,
    required List<PollOption> options,
    @JsonKey(name: 'my_option_ids')
    required List<String> myOptionIds,
    @JsonKey(name: 'total_voters')
    required int totalVoters,
    @JsonKey(name: 'winning_option_ids')
    required List<String> winningOptionIds,
    @JsonKey(name: 'created_by')
    required UserPublic? createdBy,
    @JsonKey(name: 'can_manage')
    required bool canManage,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'updated_at')
    required DateTime updatedAt,
  }) = _Poll;
  
  factory Poll.fromJson(Map<String, Object?> json) => _$PollFromJson(json);
}
