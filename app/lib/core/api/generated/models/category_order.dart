// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'category_order.freezed.dart';
part 'category_order.g.dart';

@Freezed()
abstract class CategoryOrder with _$CategoryOrder {
  const factory CategoryOrder({
    @JsonKey(name: 'category_ids')
    required List<String> categoryIds,
    @JsonKey(name: 'parent_id')
    String? parentId,
  }) = _CategoryOrder;
  
  factory CategoryOrder.fromJson(Map<String, Object?> json) => _$CategoryOrderFromJson(json);
}
