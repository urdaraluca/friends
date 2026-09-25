// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'assignable_role.dart';

part 'role_update.freezed.dart';
part 'role_update.g.dart';

@Freezed()
abstract class RoleUpdate with _$RoleUpdate {
  const factory RoleUpdate({
    required AssignableRole role,
  }) = _RoleUpdate;
  
  factory RoleUpdate.fromJson(Map<String, Object?> json) => _$RoleUpdateFromJson(json);
}
