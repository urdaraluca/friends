// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'activity_status.dart';

part 'spike_item.freezed.dart';
part 'spike_item.g.dart';

@Freezed()
abstract class SpikeItem with _$SpikeItem {
  const factory SpikeItem({
    required String id,
    required String title,
    required ActivityStatus status,
    @JsonKey(name: 'due_date') required DateTime? dueDate,
    @JsonKey(name: 'starts_at') required DateTime? startsAt,
    required String? notes,
  }) = _SpikeItem;

  factory SpikeItem.fromJson(Map<String, Object?> json) =>
      _$SpikeItemFromJson(json);
}
