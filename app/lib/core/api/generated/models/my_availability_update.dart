// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'availability_entry_write.dart';

part 'my_availability_update.freezed.dart';
part 'my_availability_update.g.dart';

/// Replaces every entry of mine with ``from_date <= date < to_date`` by ``entries``; a slot.
/// left out becomes unknown.
@Freezed()
abstract class MyAvailabilityUpdate with _$MyAvailabilityUpdate {
  const factory MyAvailabilityUpdate({
    @JsonKey(name: 'from_date')
    required DateTime fromDate,
    @JsonKey(name: 'to_date')
    required DateTime toDate,
    List<AvailabilityEntryWrite>? entries,
  }) = _MyAvailabilityUpdate;
  
  factory MyAvailabilityUpdate.fromJson(Map<String, Object?> json) => _$MyAvailabilityUpdateFromJson(json);
}
