// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'invite_status.dart';
import 'user_public.dart';

part 'invite.freezed.dart';
part 'invite.g.dart';

@Freezed()
abstract class Invite with _$Invite {
  const factory Invite({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    required String code,
    required String url,
    required InviteStatus status,
    @JsonKey(name: 'expires_at')
    required DateTime? expiresAt,
    @JsonKey(name: 'max_uses')
    required int? maxUses,
    @JsonKey(name: 'use_count')
    required int useCount,
    @JsonKey(name: 'revoked_at')
    required DateTime? revokedAt,
    @JsonKey(name: 'created_by')
    required UserPublic? createdBy,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'can_delete')
    required bool canDelete,
  }) = _Invite;
  
  factory Invite.fromJson(Map<String, Object?> json) => _$InviteFromJson(json);
}
