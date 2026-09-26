// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'recap_activity.dart';

part 'recap_wait.freezed.dart';
part 'recap_wait.g.dart';

@Freezed()
abstract class RecapWait with _$RecapWait {
  const factory RecapWait({
    required RecapActivity activity,
    required int days,
  }) = _RecapWait;
  
  factory RecapWait.fromJson(Map<String, Object?> json) => _$RecapWaitFromJson(json);
}
