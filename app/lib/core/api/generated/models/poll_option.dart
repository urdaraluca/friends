// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_public.dart';

part 'poll_option.freezed.dart';
part 'poll_option.g.dart';

@Freezed()
abstract class PollOption with _$PollOption {
  const factory PollOption({
    required String id,
    required String label,
    required String? url,
    required int position,
    @JsonKey(name: 'vote_count')
    required int voteCount,
    required List<UserPublic> voters,
    @JsonKey(name: 'added_by')
    required UserPublic? addedBy,
    @JsonKey(name: 'can_delete')
    required bool canDelete,
  }) = _PollOption;
  
  factory PollOption.fromJson(Map<String, Object?> json) => _$PollOptionFromJson(json);
}
