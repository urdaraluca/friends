// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_status.dart';

part 'wheel_filters.freezed.dart';
part 'wheel_filters.g.dart';

/// Which activities go on the wheel; the same semantics as ``list_activities``. There is no.
/// server default for ``interested_by``: the client's "Only ideas I'm interested in" toggle.
/// starts on and sends it.
@Freezed()
abstract class WheelFilters with _$WheelFilters {
  const factory WheelFilters({
    @JsonKey(name: 'include_subcategories')
    @Default(true)
    bool includeSubcategories,
    @JsonKey(name: 'include_unpriced')
    @Default(true)
    bool includeUnpriced,

    /// 1..5 statuses. Omitted or null: idea and planning.
    List<ActivityStatus>? status,
    @JsonKey(name: 'category_id')
    String? categoryId,
    @JsonKey(name: 'interested_by')
    String? interestedBy,
    @JsonKey(name: 'owner_id')
    String? ownerId,
    @JsonKey(name: 'cost_max')
    int? costMax,
    @JsonKey(name: 'due_before')
    DateTime? dueBefore,
  }) = _WheelFilters;
  
  factory WheelFilters.fromJson(Map<String, Object?> json) => _$WheelFiltersFromJson(json);
}
