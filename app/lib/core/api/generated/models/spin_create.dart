// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'wheel_filters.dart';

part 'spin_create.freezed.dart';
part 'spin_create.g.dart';

@Freezed()
abstract class SpinCreate with _$SpinCreate {
  const factory SpinCreate({
    required WheelFilters filters,
    @JsonKey(name: 'activity_ids')
    List<String>? activityIds,
  }) = _SpinCreate;
  
  factory SpinCreate.fromJson(Map<String, Object?> json) => _$SpinCreateFromJson(json);
}
