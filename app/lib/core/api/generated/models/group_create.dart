// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'group_create.freezed.dart';
part 'group_create.g.dart';

@Freezed()
abstract class GroupCreate with _$GroupCreate {
  const factory GroupCreate({
    required String name,
    @Default('EUR')
    String currency,
    @JsonKey(name: 'members_can_invite')
    @Default(true)
    bool membersCanInvite,
    @JsonKey(name: 'seed_default_categories')
    @Default(true)
    bool seedDefaultCategories,
    String? description,
    String? emoji,
    String? color,
    String? timezone,
  }) = _GroupCreate;
  
  factory GroupCreate.fromJson(Map<String, Object?> json) => _$GroupCreateFromJson(json);
}
