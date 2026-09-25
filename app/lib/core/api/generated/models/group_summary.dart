// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'role.dart';

part 'group_summary.freezed.dart';
part 'group_summary.g.dart';

@Freezed()
abstract class GroupSummary with _$GroupSummary {
  const factory GroupSummary({
    required String id,
    required String name,
    required String? emoji,
    required String? color,
    @JsonKey(name: 'member_count')
    required int memberCount,
    @JsonKey(name: 'my_role')
    required Role myRole,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
  }) = _GroupSummary;
  
  factory GroupSummary.fromJson(Map<String, Object?> json) => _$GroupSummaryFromJson(json);
}
