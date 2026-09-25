// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'invite_create.freezed.dart';
part 'invite_create.g.dart';

@Freezed()
abstract class InviteCreate with _$InviteCreate {
  const factory InviteCreate({
    @JsonKey(name: 'max_uses')
    int? maxUses,
    @JsonKey(name: 'expires_in_hours')
    @Default(168)
    int expiresInHours,
    @JsonKey(name: 'never_expires')
    @Default(false)
    bool neverExpires,
  }) = _InviteCreate;
  
  factory InviteCreate.fromJson(Map<String, Object?> json) => _$InviteCreateFromJson(json);
}
