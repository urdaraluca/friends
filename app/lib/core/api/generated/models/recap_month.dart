// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'recap_month.freezed.dart';
part 'recap_month.g.dart';

@Freezed()
abstract class RecapMonth with _$RecapMonth {
  const factory RecapMonth({
    required DateTime month,
    required int count,
  }) = _RecapMonth;
  
  factory RecapMonth.fromJson(Map<String, Object?> json) => _$RecapMonthFromJson(json);
}
