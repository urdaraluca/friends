// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_status.dart';

part 'status_change.freezed.dart';
part 'status_change.g.dart';

@Freezed()
abstract class StatusChange with _$StatusChange {
  const factory StatusChange({
    required ActivityStatus status,
  }) = _StatusChange;
  
  factory StatusChange.fromJson(Map<String, Object?> json) => _$StatusChangeFromJson(json);
}
