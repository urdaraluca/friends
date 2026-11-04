// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'password_reset.freezed.dart';
part 'password_reset.g.dart';

@Freezed()
abstract class PasswordReset with _$PasswordReset {
  const factory PasswordReset({
    required String token,
    @JsonKey(name: 'new_password')
    required String newPassword,
  }) = _PasswordReset;
  
  factory PasswordReset.fromJson(Map<String, Object?> json) => _$PasswordResetFromJson(json);
}
