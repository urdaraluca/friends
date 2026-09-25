// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'invite_group_preview.dart';
import 'invite_status.dart';

part 'invite_preview.freezed.dart';
part 'invite_preview.g.dart';

/// Public: carries no IDs.
@Freezed()
abstract class InvitePreview with _$InvitePreview {
  const factory InvitePreview({
    required String code,
    required InviteStatus status,
    required InviteGroupPreview group,
    @JsonKey(name: 'invited_by_name')
    required String? invitedByName,
    @JsonKey(name: 'expires_at')
    required DateTime? expiresAt,
  }) = _InvitePreview;
  
  factory InvitePreview.fromJson(Map<String, Object?> json) => _$InvitePreviewFromJson(json);
}
