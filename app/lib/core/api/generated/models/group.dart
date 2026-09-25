// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'role.dart';
import 'user_public.dart';

part 'group.freezed.dart';
part 'group.g.dart';

@Freezed()
abstract class Group with _$Group {
  const factory Group({
    required String id,
    required String name,
    required String? emoji,
    required String? color,
    @JsonKey(name: 'member_count')
    required int memberCount,
    @JsonKey(name: 'my_role')
    required Role myRole,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    required String? description,
    required String currency,
    required String timezone,
    @JsonKey(name: 'members_can_invite')
    required bool membersCanInvite,
    @JsonKey(name: 'created_by')
    required UserPublic? createdBy,
    @JsonKey(name: 'updated_at')
    required DateTime updatedAt,
  }) = _Group;
  
  factory Group.fromJson(Map<String, Object?> json) => _$GroupFromJson(json);
}
