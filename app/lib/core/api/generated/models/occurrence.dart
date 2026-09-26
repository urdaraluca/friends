// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'event_kind.dart';
import 'occurrence_source.dart';

part 'occurrence.freezed.dart';
part 'occurrence.g.dart';

/// One calendar entry: an occurrence of an event, or a member's birthday.
@Freezed()
abstract class Occurrence with _$Occurrence {
  const factory Occurrence({
    @JsonKey(name: 'occurrence_key')
    required String occurrenceKey,
    required OccurrenceSource source,
    @JsonKey(name: 'event_id')
    required String? eventId,
    @JsonKey(name: 'user_id')
    required String? userId,
    @JsonKey(name: 'group_id')
    required String? groupId,
    required EventKind kind,
    required String title,
    @JsonKey(name: 'all_day')
    required bool allDay,
    @JsonKey(name: 'starts_at')
    required DateTime? startsAt,
    @JsonKey(name: 'ends_at')
    required DateTime? endsAt,
    @JsonKey(name: 'start_date')
    required DateTime? startDate,
    @JsonKey(name: 'end_date')
    required DateTime? endDate,
    required String? timezone,
    @JsonKey(name: 'category_id')
    required String? categoryId,
    required String? color,
    @JsonKey(name: 'activity_id')
    required String? activityId,
    @JsonKey(name: 'is_recurring')
    required bool isRecurring,
    @JsonKey(name: 'can_edit')
    required bool canEdit,
  }) = _Occurrence;
  
  factory Occurrence.fromJson(Map<String, Object?> json) => _$OccurrenceFromJson(json);
}
