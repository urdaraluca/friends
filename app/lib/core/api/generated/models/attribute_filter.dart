// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'attribute_op.dart';

part 'attribute_filter.freezed.dart';
part 'attribute_filter.g.dart';

/// Matches activities whose custom attribute ``key`` (contract section 6) satisfies ``op``.
/// An activity without the attribute, or with a value of another type, never matches.
@Freezed()
abstract class AttributeFilter with _$AttributeFilter {
  const factory AttributeFilter({
    required String key,
    required AttributeOp op,
    required String value,
  }) = _AttributeFilter;
  
  factory AttributeFilter.fromJson(Map<String, Object?> json) => _$AttributeFilterFromJson(json);
}
