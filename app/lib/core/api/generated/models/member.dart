// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'birthday_public.dart';
import 'role.dart';
import 'user_public.dart';

part 'member.freezed.dart';
part 'member.g.dart';

@Freezed()
abstract class Member with _$Member {
  const factory Member({
    required UserPublic user,
    required Role role,
    @JsonKey(name: 'joined_at')
    required DateTime joinedAt,
    required BirthdayPublic? birthday,
    @JsonKey(name: 'show_birthday')
    required bool? showBirthday,
  }) = _Member;
  
  factory Member.fromJson(Map<String, Object?> json) => _$MemberFromJson(json);
}
