// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'recap_category.freezed.dart';
part 'recap_category.g.dart';

/// A top-level category and how many memories fall under it (its subcategories.
/// included).
@Freezed()
abstract class RecapCategory with _$RecapCategory {
  const factory RecapCategory({
    required String id,
    required String name,
    required String? color,
    required String? icon,
    required int count,
  }) = _RecapCategory;
  
  factory RecapCategory.fromJson(Map<String, Object?> json) => _$RecapCategoryFromJson(json);
}
