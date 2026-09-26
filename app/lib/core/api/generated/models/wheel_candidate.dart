// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'wheel_candidate.freezed.dart';
part 'wheel_candidate.g.dart';

/// A slice of the wheel, as it was at spin time.
@Freezed()
abstract class WheelCandidate with _$WheelCandidate {
  const factory WheelCandidate({
    required String id,
    required String title,
    @JsonKey(name: 'category_id')
    required String? categoryId,
    required String? color,
  }) = _WheelCandidate;
  
  factory WheelCandidate.fromJson(Map<String, Object?> json) => _$WheelCandidateFromJson(json);
}
