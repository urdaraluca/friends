// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'occurrence_edit.freezed.dart';
part 'occurrence_edit.g.dart';

/// An edited occurrence; null fields are the series'.
@Freezed()
abstract class OccurrenceEdit with _$OccurrenceEdit {
  const factory OccurrenceEdit({
    @JsonKey(name: 'occurrence_key')
    required String occurrenceKey,
    required String? title,
    @JsonKey(name: 'starts_at')
    required DateTime? startsAt,
    @JsonKey(name: 'ends_at')
    required DateTime? endsAt,
    @JsonKey(name: 'start_date')
    required DateTime? startDate,
    @JsonKey(name: 'end_date')
    required DateTime? endDate,
  }) = _OccurrenceEdit;
  
  factory OccurrenceEdit.fromJson(Map<String, Object?> json) => _$OccurrenceEditFromJson(json);
}
