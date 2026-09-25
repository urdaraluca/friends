// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'invite_group_preview.freezed.dart';
part 'invite_group_preview.g.dart';

@Freezed()
abstract class InviteGroupPreview with _$InviteGroupPreview {
  const factory InviteGroupPreview({
    required String name,
    required String? emoji,
    required String? color,
    @JsonKey(name: 'member_count')
    required int memberCount,
  }) = _InviteGroupPreview;
  
  factory InviteGroupPreview.fromJson(Map<String, Object?> json) => _$InviteGroupPreviewFromJson(json);
}
