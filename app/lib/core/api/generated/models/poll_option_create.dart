// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, unused_import, invalid_annotation_target, unnecessary_import

import 'package:freezed_annotation/freezed_annotation.dart';

part 'poll_option_create.freezed.dart';
part 'poll_option_create.g.dart';

@Freezed()
abstract class PollOptionCreate with _$PollOptionCreate {
  const factory PollOptionCreate({
    required String label,
    String? url,
  }) = _PollOptionCreate;
  
  factory PollOptionCreate.fromJson(Map<String, Object?> json) => _$PollOptionCreateFromJson(json);
}
