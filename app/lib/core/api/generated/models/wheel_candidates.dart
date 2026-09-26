// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_summary.dart';

part 'wheel_candidates.freezed.dart';
part 'wheel_candidates.g.dart';

@Freezed()
abstract class WheelCandidates with _$WheelCandidates {
  const factory WheelCandidates({
    required List<ActivitySummary> items,
    required int total,
  }) = _WheelCandidates;
  
  factory WheelCandidates.fromJson(Map<String, Object?> json) => _$WheelCandidatesFromJson(json);
}
