// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_public.dart';
import 'wheel_candidate.dart';
import 'wheel_filters.dart';

part 'wheel_spin.freezed.dart';
part 'wheel_spin.g.dart';

@Freezed()
abstract class WheelSpin with _$WheelSpin {
  const factory WheelSpin({
    required String id,
    @JsonKey(name: 'group_id')
    required String groupId,
    @JsonKey(name: 'spun_by')
    required UserPublic? spunBy,
    required WheelFilters filters,
    required List<WheelCandidate> candidates,
    @JsonKey(name: 'result_index')
    required int resultIndex,
    required WheelCandidate result,
    @JsonKey(name: 'result_activity_id')
    required String? resultActivityId,
    @JsonKey(name: 'accepted_at')
    required DateTime? acceptedAt,
    @JsonKey(name: 'accepted_by')
    required UserPublic? acceptedBy,
    @JsonKey(name: 'created_at')
    required DateTime createdAt,
  }) = _WheelSpin;
  
  factory WheelSpin.fromJson(Map<String, Object?> json) => _$WheelSpinFromJson(json);
}
