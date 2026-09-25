// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'birthday.dart';

part 'me.freezed.dart';
part 'me.g.dart';

@Freezed()
abstract class Me with _$Me {
  const factory Me({
    required String id,
    required String email,
    @JsonKey(name: 'display_name')
    required String displayName,
    @JsonKey(name: 'avatar_url')
    required String? avatarUrl,
    required Birthday? birthday,
    required String timezone,
    required String? locale,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
  }) = _Me;
  
  factory Me.fromJson(Map<String, Object?> json) => _$MeFromJson(json);
}
