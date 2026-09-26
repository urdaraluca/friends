// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'occurrence.dart';

part 'calendar_response.freezed.dart';
part 'calendar_response.g.dart';

@Freezed()
abstract class CalendarResponse with _$CalendarResponse {
  const factory CalendarResponse({
    @JsonKey(name: 'from_date')
    required DateTime fromDate,
    @JsonKey(name: 'to_date')
    required DateTime toDate,
    required String tz,
    required List<Occurrence> occurrences,
  }) = _CalendarResponse;
  
  factory CalendarResponse.fromJson(Map<String, Object?> json) => _$CalendarResponseFromJson(json);
}
