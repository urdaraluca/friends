// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'event_kind.dart';

part 'event_ref.freezed.dart';
part 'event_ref.g.dart';

/// A calendar event linked to an activity (``Activity.events``, by ``window_start``).
@Freezed()
abstract class EventRef with _$EventRef {
  const factory EventRef({
    required String id,
    required EventKind kind,
    required String title,
    @JsonKey(name: 'all_day')
    required bool allDay,
    @JsonKey(name: 'starts_at')
    required DateTime? startsAt,
    @JsonKey(name: 'start_date')
    required DateTime? startDate,
    required String? rrule,
  }) = _EventRef;
  
  factory EventRef.fromJson(Map<String, Object?> json) => _$EventRefFromJson(json);
}
