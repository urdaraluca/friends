// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'password_change.freezed.dart';
part 'password_change.g.dart';

@Freezed()
abstract class PasswordChange with _$PasswordChange {
  const factory PasswordChange({
    @JsonKey(name: 'current_password')
    required String currentPassword,
    @JsonKey(name: 'new_password')
    required String newPassword,
  }) = _PasswordChange;
  
  factory PasswordChange.fromJson(Map<String, Object?> json) => _$PasswordChangeFromJson(json);
}
