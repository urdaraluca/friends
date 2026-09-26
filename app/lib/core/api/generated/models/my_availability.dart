// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'availability_entry.dart';

part 'my_availability.freezed.dart';
part 'my_availability.g.dart';

@Freezed()
abstract class MyAvailability with _$MyAvailability {
  const factory MyAvailability({
    @JsonKey(name: 'from_date')
    required DateTime fromDate,
    @JsonKey(name: 'to_date')
    required DateTime toDate,
    required List<AvailabilityEntry> entries,
  }) = _MyAvailability;
  
  factory MyAvailability.fromJson(Map<String, Object?> json) => _$MyAvailabilityFromJson(json);
}
