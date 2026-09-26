// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'availability_slot.dart';
import 'availability_status.dart';

part 'availability_entry_write.freezed.dart';
part 'availability_entry_write.g.dart';

@Freezed()
abstract class AvailabilityEntryWrite with _$AvailabilityEntryWrite {
  const factory AvailabilityEntryWrite({
    required DateTime date,
    required AvailabilitySlot slot,
    required AvailabilityStatus status,
  }) = _AvailabilityEntryWrite;
  
  factory AvailabilityEntryWrite.fromJson(Map<String, Object?> json) => _$AvailabilityEntryWriteFromJson(json);
}
