// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'event_kind.dart';

part 'event_write.freezed.dart';
part 'event_write.g.dart';

/// A series. Rules (contract section 5.8):.
///
/// - ``one_time``: no ``rrule``. ``recurring``: an ``rrule`` from the allowed subset (stored.
///   canonical). ``birthday``: all-day, ``end_date`` null or equal to ``start_date``, ``rrule``.
///   null or ``FREQ=YEARLY`` (29 February is allowed).
/// - All-day: ``start_date`` (``end_date`` null means the same day) and no instants. Timed:.
///   ``starts_at`` < ``ends_at`` and no dates. At most 30 days long.
/// - ``timezone`` null means the group's.
@Freezed()
abstract class EventWrite with _$EventWrite {
  const factory EventWrite({
    required EventKind kind,
    required String title,
    @JsonKey(name: 'all_day')
    required bool allDay,
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
  }) = _EventWrite;
  
  factory EventWrite.fromJson(Map<String, Object?> json) => _$EventWriteFromJson(json);
}
