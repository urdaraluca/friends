// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'password_reset_request.freezed.dart';
part 'password_reset_request.g.dart';

@Freezed()
abstract class PasswordResetRequest with _$PasswordResetRequest {
  const factory PasswordResetRequest({
    required String email,
  }) = _PasswordResetRequest;
  
  factory PasswordResetRequest.fromJson(Map<String, Object?> json) => _$PasswordResetRequestFromJson(json);
}
