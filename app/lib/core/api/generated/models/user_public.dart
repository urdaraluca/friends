// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_public.freezed.dart';
part 'user_public.g.dart';

@Freezed()
abstract class UserPublic with _$UserPublic {
  const factory UserPublic({
    required String id,
    @JsonKey(name: 'display_name')
    required String displayName,
    @JsonKey(name: 'avatar_url')
    required String? avatarUrl,
  }) = _UserPublic;
  
  factory UserPublic.fromJson(Map<String, Object?> json) => _$UserPublicFromJson(json);
}
