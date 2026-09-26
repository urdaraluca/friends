// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'occurrence_ref.freezed.dart';
part 'occurrence_ref.g.dart';

/// The next occurrence of an activity's linked events (``ActivitySummary.next_occurrence``).
@Freezed()
abstract class OccurrenceRef with _$OccurrenceRef {
  const factory OccurrenceRef({
    @JsonKey(name: 'event_id')
    required String eventId,
    @JsonKey(name: 'occurrence_key')
    required String occurrenceKey,
    @JsonKey(name: 'all_day')
    required bool allDay,
    @JsonKey(name: 'starts_at')
    required DateTime? startsAt,
    @JsonKey(name: 'start_date')
    required DateTime? startDate,
  }) = _OccurrenceRef;
  
  factory OccurrenceRef.fromJson(Map<String, Object?> json) => _$OccurrenceRefFromJson(json);
}
