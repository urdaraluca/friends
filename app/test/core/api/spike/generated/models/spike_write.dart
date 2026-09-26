// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_status.dart';

part 'spike_write.freezed.dart';
part 'spike_write.g.dart';

@Freezed()
abstract class SpikeWrite with _$SpikeWrite {
  const factory SpikeWrite({
    required String title,
    @JsonKey(name: 'due_date') DateTime? dueDate,
    @JsonKey(name: 'starts_at') DateTime? startsAt,
    String? notes,
    @Default(ActivityStatus.idea) ActivityStatus status,
  }) = _SpikeWrite;

  factory SpikeWrite.fromJson(Map<String, Object?> json) =>
      _$SpikeWriteFromJson(json);
}
