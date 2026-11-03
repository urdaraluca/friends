// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'email_verification.freezed.dart';
part 'email_verification.g.dart';

@Freezed()
abstract class EmailVerification with _$EmailVerification {
  const factory EmailVerification({
    required String token,
  }) = _EmailVerification;
  
  factory EmailVerification.fromJson(Map<String, Object?> json) => _$EmailVerificationFromJson(json);
}
