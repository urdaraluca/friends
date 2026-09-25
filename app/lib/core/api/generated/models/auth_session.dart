// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'group_summary.dart';
import 'me.dart';
import 'token_pair.dart';

part 'auth_session.freezed.dart';
part 'auth_session.g.dart';

@Freezed()
abstract class AuthSession with _$AuthSession {
  const factory AuthSession({
    required Me user,
    required TokenPair tokens,
    @JsonKey(name: 'joined_group')
    required GroupSummary? joinedGroup,
  }) = _AuthSession;
  
  factory AuthSession.fromJson(Map<String, Object?> json) => _$AuthSessionFromJson(json);
}
