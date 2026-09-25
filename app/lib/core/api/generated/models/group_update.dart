// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'group_update.freezed.dart';
part 'group_update.g.dart';

@Freezed()
abstract class GroupUpdate with _$GroupUpdate {
  const factory GroupUpdate({
    required String name,
    required String currency,
    required String timezone,
    @JsonKey(name: 'members_can_invite')
    required bool membersCanInvite,
    String? description,
    String? emoji,
    String? color,
  }) = _GroupUpdate;
  
  factory GroupUpdate.fromJson(Map<String, Object?> json) => _$GroupUpdateFromJson(json);
}
