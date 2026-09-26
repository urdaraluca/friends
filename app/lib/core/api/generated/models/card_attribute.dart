// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'field_type.dart';

part 'card_attribute.freezed.dart';
part 'card_attribute.g.dart';

/// A custom-field value shown on the backlog card (its definition has ``show_on_card``).
@Freezed()
abstract class CardAttribute with _$CardAttribute {
  const factory CardAttribute({
    required String key,
    required String label,
    required FieldType type,
    required dynamic value,
  }) = _CardAttribute;
  
  factory CardAttribute.fromJson(Map<String, Object?> json) => _$CardAttributeFromJson(json);
}
