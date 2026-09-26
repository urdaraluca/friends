// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'user_public.dart';

part 'recap_planner.freezed.dart';
part 'recap_planner.g.dart';

@Freezed()
abstract class RecapPlanner with _$RecapPlanner {
  const factory RecapPlanner({
    required UserPublic user,
    required int score,
    required int ideas,
    required int events,
    required int polls,
    required int done,
  }) = _RecapPlanner;
  
  factory RecapPlanner.fromJson(Map<String, Object?> json) => _$RecapPlannerFromJson(json);
}
