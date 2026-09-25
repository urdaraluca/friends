// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'member_settings_update.freezed.dart';
part 'member_settings_update.g.dart';

@Freezed()
abstract class MemberSettingsUpdate with _$MemberSettingsUpdate {
  const factory MemberSettingsUpdate({
    @JsonKey(name: 'show_birthday')
    required bool showBirthday,
  }) = _MemberSettingsUpdate;
  
  factory MemberSettingsUpdate.fromJson(Map<String, Object?> json) => _$MemberSettingsUpdateFromJson(json);
}
