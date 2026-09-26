// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'best_day.dart';
import 'day_availability.dart';

part 'group_availability.freezed.dart';
part 'group_availability.g.dart';

@Freezed()
abstract class GroupAvailability with _$GroupAvailability {
  const factory GroupAvailability({
    @JsonKey(name: 'from_date')
    required DateTime fromDate,
    @JsonKey(name: 'to_date')
    required DateTime toDate,
    @JsonKey(name: 'member_count')
    required int memberCount,
    required List<DayAvailability> days,
    @JsonKey(name: 'best_days')
    required List<BestDay> bestDays,
  }) = _GroupAvailability;
  
  factory GroupAvailability.fromJson(Map<String, Object?> json) => _$GroupAvailabilityFromJson(json);
}
