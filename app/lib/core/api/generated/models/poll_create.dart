// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

import 'poll_option_create.dart';

part 'poll_create.freezed.dart';
part 'poll_create.g.dart';

@Freezed()
abstract class PollCreate with _$PollCreate {
  const factory PollCreate({
    required String question,
    required List<PollOptionCreate> options,
    @JsonKey(name: 'closes_at')
    DateTime? closesAt,
    @JsonKey(name: 'allow_multiple')
    @Default(false)
    bool allowMultiple,
  }) = _PollCreate;
  
  factory PollCreate.fromJson(Map<String, Object?> json) => _$PollCreateFromJson(json);
}
