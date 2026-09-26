// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'event_kind.dart';

part 'event_update.freezed.dart';
part 'event_update.g.dart';

/// The complete new state of the whole series.
@Freezed()
abstract class EventUpdate with _$EventUpdate {
  const factory EventUpdate({
    required EventKind kind,
    required String title,
    @JsonKey(name: 'all_day')
    required bool allDay,
    required int version,
    String? description,
    @JsonKey(name: 'starts_at')
    DateTime? startsAt,
    @JsonKey(name: 'ends_at')
    DateTime? endsAt,
    @JsonKey(name: 'start_date')
    DateTime? startDate,
    @JsonKey(name: 'end_date')
    DateTime? endDate,
    String? timezone,
    String? rrule,
    @JsonKey(name: 'category_id')
    String? categoryId,
    @JsonKey(name: 'activity_id')
    String? activityId,
    @JsonKey(name: 'location_name')
    String? locationName,
    String? address,
  }) = _EventUpdate;
  
  factory EventUpdate.fromJson(Map<String, Object?> json) => _$EventUpdateFromJson(json);
}
