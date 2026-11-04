// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'invite_email.freezed.dart';
part 'invite_email.g.dart';

@Freezed()
abstract class InviteEmail with _$InviteEmail {
  const factory InviteEmail({
    required String email,
  }) = _InviteEmail;
  
  factory InviteEmail.fromJson(Map<String, Object?> json) => _$InviteEmailFromJson(json);
}
