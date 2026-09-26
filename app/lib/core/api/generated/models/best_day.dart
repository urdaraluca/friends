// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'best_day.freezed.dart';
part 'best_day.g.dart';

@Freezed()
abstract class BestDay with _$BestDay {
  const factory BestDay({
    required DateTime date,
    required num score,
    required int free,
    required int maybe,
    required int busy,
    required int unknown,
  }) = _BestDay;
  
  factory BestDay.fromJson(Map<String, Object?> json) => _$BestDayFromJson(json);
}
