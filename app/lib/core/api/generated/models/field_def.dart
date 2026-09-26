// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'field_type.dart';

part 'field_def.freezed.dart';
part 'field_def.g.dart';

/// A custom field of a category (contract section 6.1). The list order is the display order.
///
/// Shape rules are checked here, so errors point at e.g. ``field_defs.2.options``. Rules that.
/// need other categories (key conflicts, type changes) are checked by the service.
@Freezed()
abstract class FieldDef with _$FieldDef {
  const factory FieldDef({
    required String key,
    required String label,
    required FieldType type,
    @JsonKey(name: 'show_on_card')
    @Default(false)
    bool showOnCard,
    List<String>? options,
    num? min,
    num? max,
  }) = _FieldDef;
  
  factory FieldDef.fromJson(Map<String, Object?> json) => _$FieldDefFromJson(json);
}
