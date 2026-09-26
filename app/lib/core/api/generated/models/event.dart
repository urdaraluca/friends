// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'event_kind.dart';
import 'user_public.dart';

part 'event.freezed.dart';
part 'event.g.dart';

@Freezed()
abstract class Event with _$Event {
  const factory Event({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    required EventKind kind,
    required String title,
    required String? description,
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
    required String timezone,
    required String? rrule,
    @JsonKey(name: 'category_id')
    required String? categoryId,
    required String? color,
    @JsonKey(name: 'activity_id')
    required String? activityId,
    @JsonKey(name: 'location_name')
    required String? locationName,
    required String? address,
    @JsonKey(name: 'cancelled_occurrence_keys')
    required List<String> cancelledOccurrenceKeys,
    required int version,
    @JsonKey(name: 'created_by')
    required UserPublic? createdBy,
    @JsonKey(name: 'can_edit')
    required bool canEdit,
    @JsonKey(name: 'can_delete')
    required bool canDelete,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
    @JsonKey(name: 'updated_at')
    required DateTime updatedAt,
  }) = _Event;
  
  factory Event.fromJson(Map<String, Object?> json) => _$EventFromJson(json);
}
