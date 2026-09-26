// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'poll_update.freezed.dart';
part 'poll_update.g.dart';

/// The complete new state (``allow_multiple`` can't change).
@Freezed()
abstract class PollUpdate with _$PollUpdate {
  const factory PollUpdate({
    required String question,
    @JsonKey(name: 'closes_at')
    DateTime? closesAt,
  }) = _PollUpdate;
  
  factory PollUpdate.fromJson(Map<String, Object?> json) => _$PollUpdateFromJson(json);
}
