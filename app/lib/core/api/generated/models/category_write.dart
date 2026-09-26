// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'field_def.dart';

part 'category_write.freezed.dart';
part 'category_write.g.dart';

@Freezed()
abstract class CategoryWrite with _$CategoryWrite {
  const factory CategoryWrite({
    required String name,
    @JsonKey(name: 'parent_id')
    String? parentId,
    String? color,
    String? icon,
    int? position,
    @JsonKey(name: 'field_defs')
    List<FieldDef>? fieldDefs,
  }) = _CategoryWrite;
  
  factory CategoryWrite.fromJson(Map<String, Object?> json) => _$CategoryWriteFromJson(json);
}
