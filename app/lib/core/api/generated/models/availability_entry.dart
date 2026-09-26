// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'availability_slot.dart';
import 'availability_status.dart';

part 'availability_entry.freezed.dart';
part 'availability_entry.g.dart';

@Freezed()
abstract class AvailabilityEntry with _$AvailabilityEntry {
  const factory AvailabilityEntry({
    required DateTime date,
    required AvailabilitySlot slot,
    required AvailabilityStatus status,
  }) = _AvailabilityEntry;
  
  factory AvailabilityEntry.fromJson(Map<String, Object?> json) => _$AvailabilityEntryFromJson(json);
}
