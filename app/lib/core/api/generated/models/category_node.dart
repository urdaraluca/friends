// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'category.dart';
import 'field_def.dart';
import 'user_public.dart';

part 'category_node.freezed.dart';
part 'category_node.g.dart';

@Freezed()
abstract class CategoryNode with _$CategoryNode {
  const factory CategoryNode({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    @JsonKey(name: 'parent_id')
    required String? parentId,
    required String name,
    required String? color,
    @JsonKey(name: 'effective_color')
    required String? effectiveColor,
    required String? icon,
    required int position,
    @JsonKey(name: 'field_defs')
    required List<FieldDef> fieldDefs,
    @JsonKey(name: 'effective_field_defs')
    required List<FieldDef> effectiveFieldDefs,
    @JsonKey(name: 'created_by')
    required UserPublic? createdBy,
    @JsonKey(name: 'can_edit')
    required bool canEdit,
    @JsonKey(name: 'can_delete')
    required bool canDelete,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'updated_at')
    required DateTime updatedAt,
    required List<Category> subcategories,
  }) = _CategoryNode;
  
  factory CategoryNode.fromJson(Map<String, Object?> json) => _$CategoryNodeFromJson(json);
}
