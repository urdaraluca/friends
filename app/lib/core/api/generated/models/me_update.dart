// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'birthday.dart';

part 'me_update.freezed.dart';
part 'me_update.g.dart';

@Freezed()
abstract class MeUpdate with _$MeUpdate {
  const factory MeUpdate({
    @JsonKey(name: 'display_name')
    required String displayName,
    required String timezone,
    Birthday? birthday,
    String? locale,
    @JsonKey(name: 'avatar_url')
    String? avatarUrl,
  }) = _MeUpdate;
  
  factory MeUpdate.fromJson(Map<String, Object?> json) => _$MeUpdateFromJson(json);
}
