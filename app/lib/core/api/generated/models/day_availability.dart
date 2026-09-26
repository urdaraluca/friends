// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'slot_counts.dart';

part 'day_availability.freezed.dart';
part 'day_availability.g.dart';

@Freezed()
abstract class DayAvailability with _$DayAvailability {
  const factory DayAvailability({
    required DateTime date,
    required num score,
    required List<SlotCounts> slots,
  }) = _DayAvailability;
  
  factory DayAvailability.fromJson(Map<String, Object?> json) => _$DayAvailabilityFromJson(json);
}
