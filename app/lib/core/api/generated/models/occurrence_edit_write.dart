// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'occurrence_edit_write.freezed.dart';
part 'occurrence_edit_write.g.dart';

/// Edits one occurrence of a recurring event (contract section 5.6). Null keeps the.
/// series' value; at least one field must be set.
///
/// - ``title``: another title for this occurrence.
/// - Timed events: ``starts_at`` and ``ends_at`` together (the same rules as the series').
/// - All-day events: ``start_date``, and ``end_date`` (null keeps the series' length).
@Freezed()
abstract class OccurrenceEditWrite with _$OccurrenceEditWrite {
  const factory OccurrenceEditWrite({
    String? title,
    @JsonKey(name: 'starts_at')
    DateTime? startsAt,
    @JsonKey(name: 'ends_at')
    DateTime? endsAt,
    @JsonKey(name: 'start_date')
    DateTime? startDate,
    @JsonKey(name: 'end_date')
    DateTime? endDate,
  }) = _OccurrenceEditWrite;
  
  factory OccurrenceEditWrite.fromJson(Map<String, Object?> json) => _$OccurrenceEditWriteFromJson(json);
}
